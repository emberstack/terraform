# Azure Public DNS Zone

Creates an Azure public DNS zone (`Microsoft.Network/dnsZones`) with optional SOA record customization, zone-scope IAM role assignments, and parent-zone NS delegation in one apply.

## Why this exists alongside the AVM module

The AVM module [`Azure/avm-res-network-dnszone/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-network-dnszone/azurerm/latest) covers zone creation and inline record-set creation, but does not (as of v0.2.x) expose:

- **SOA record customization** — email, TTLs, expiration tuning. AVM uses provider defaults only.
- **Zone-scope `role_assignments`** — the standard AVM IAM interface block is absent.
- **Parent-zone NS delegation** — there is no hook for inserting an NS record into a parent zone, which is the load-bearing primitive for multi-level public-DNS hierarchies (e.g., `acme.example` → `dev.acme.example` → `azr.dev.acme.example`).

This module mirrors the AVM input shape where AVM exists (`name`, `resource_group_name`, `tags`, `role_assignments`) and fills in the three gaps.

## Usage

### Greenfield zone with SOA, IAM, and parent delegation

```hcl
module "dev_zone" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-dnszone?ref=v0.1.0"

  name                = "dev.acme.example"
  resource_group_name = "dev-platform-dns"
  tags                = local.tags

  soa_record = {
    email       = "hostmaster.dev.acme.example"
    ttl         = 3600
    minimum_ttl = 300
  }

  role_assignments = {
    operators = {
      role_definition_id_or_name = "DNS Zone Contributor"
      principal_id               = data.azuread_group.dns_operators.object_id
      principal_type             = "Group"
    }
  }

  parent_zone = {
    zone_id         = "/subscriptions/<sub>/resourceGroups/global-platform-dns/providers/Microsoft.Network/dnszones/acme.example"
    delegation_name = "dev"
    delegation_ttl  = 3600
  }
}
```

### Bare zone (no SOA tweaks, no IAM, no delegation)

```hcl
module "zone" {
  source = "..."

  name                = "example.com"
  resource_group_name = "platform-dns"
  tags                = local.tags
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | — | **Required.** Fully-qualified DNS zone name. |
| `resource_group_name` | `string` | — | **Required.** Existing RG (the module does not create it). |
| `tags` | `map(string)` | `{}` | Applied to the zone. (NS delegation tags are set on `parent_zone.tags` explicitly, not inherited.) |
| `soa_record` | `object` | `null` | SOA overrides. `email` is required when set. |
| `role_assignments` | `map(object)` | `{}` | Zone-scope role assignments. AVM-shape interface block. |
| `parent_zone` | `object` | `null` | Parent-zone NS delegation. Set to wire delegation in the same apply. |

### `soa_record` shape

| Field | Type | Default | Description |
|---|---|---|---|
| `email` | `string` | — | **Required when set.** SOA RNAME (in DNS dotted form, e.g., `hostmaster.example.com`). |
| `expire_time` | `number` | provider default | SOA EXPIRE seconds. |
| `minimum_ttl` | `number` | provider default | SOA MINIMUM/Negative caching TTL. |
| `refresh_time` | `number` | provider default | SOA REFRESH seconds. |
| `retry_time` | `number` | provider default | SOA RETRY seconds. |
| `ttl` | `number` | provider default | TTL of the SOA record itself. |
| `tags` | `map(string)` | `null` | Tags on the SOA record (rarely useful — kept for parity with the underlying provider). |

### `role_assignments[*]` shape

| Field | Type | Default | Description |
|---|---|---|---|
| `role_definition_id_or_name` | `string` | — | **Required.** Either a full `/subscriptions/.../roleDefinitions/<uuid>` ID or a built-in role name (`DNS Zone Contributor`, etc.). |
| `principal_id` | `string` | — | **Required.** Object ID of the user/group/SP. |
| `principal_type` | `string` | `null` | `User`, `Group`, `ServicePrincipal`, etc. Recommended to set explicitly. |
| `description` | `string` | `null` | Description of the assignment. |
| `condition` | `string` | `null` | ABAC condition. |
| `condition_version` | `string` | `null` | ABAC condition version. |
| `skip_service_principal_aad_check` | `bool` | `false` | Skip Entra propagation check (use when assigning a brand-new SP). |
| `delegated_managed_identity_resource_id` | `string` | `null` | For delegated MI scenarios. |

### `parent_zone` shape

| Field | Type | Default | Description |
|---|---|---|---|
| `zone_id` | `string` | — | **Required.** ARM resource ID of the parent DNS zone. The parent's RG and zone name are parsed from this. |
| `delegation_name` | `string` | — | **Required.** Subdomain label to delegate (e.g., `dev` to delegate `dev.example.com` from `example.com`). |
| `delegation_ttl` | `number` | `3600` | TTL of the NS record in the parent zone. |
| `delegation_tags` | `map(string)` | `{}` | Tags applied to the NS delegation record. The zone's `var.tags` are NOT inherited — set explicitly. |

## Outputs

| Name | Description |
|---|---|
| `resource_id` | Resource ID of the public DNS zone. |
| `name` | Zone name. |
| `resource_group_name` | RG name (echo of input). |
| `name_servers` | Azure-assigned name servers (4 entries). |
| `role_assignments` | Map of created role assignments (`id`, `principal_id`). |
| `delegation` | Parent-zone NS record details (`resource_id`, `name`, `fqdn`, `parent_zone_id`, `parent_zone_name`) — `null` when `parent_zone` is not set. |

## Related modules

- [`azure-ptn-network-dnszone-records`](../azure-ptn-network-dnszone-records/) — manage DNS records (A, AAAA, CNAME, MX, NS, PTR, SRV, TXT, CAA) against any existing zone (this module's output, an AVM-managed zone, or a manually-created one).

### Adding records to the zone

```hcl
module "dev_zone" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-dnszone?ref=v0.1.0"

  name                = "dev.acme.example"
  resource_group_name = "dev-platform-dns"
  tags                = local.tags
}

module "dev_zone_records" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-network-dnszone-records?ref=v0.1.0"

  dns_zone_resource_id = module.dev_zone.resource_id
  tags                 = local.tags

  dns_zone_records = {
    api = {
      name      = "api"
      type      = "A"
      ttl       = 300
      a_records = ["10.0.0.10"]
    }
    www = {
      name         = "www"
      type         = "CNAME"
      cname_record = "dev.acme.example"
    }
    spf = {
      name        = "@"
      type        = "TXT"
      txt_records = ["v=spf1 include:_spf.example.com -all"]
    }
  }
}
```

## Requirements

- Terraform `>= 1.15`
- `hashicorp/azurerm` `>= 4.81, < 5.0`
- The deploying principal must have:
  - `DNS Zone Contributor` (or equivalent) on the resource group hosting the zone.
  - `DNS Zone Contributor` (or equivalent) on the **parent zone's** resource group, when `parent_zone` is set.
  - `Role Based Access Control Administrator` (or equivalent) on the zone, when `role_assignments` is set.

## Notes

- **Public zones are global.** No `location` input; Azure tracks zones at the subscription level, not per-region.
- **Parent zone in a different subscription.** This module uses the default `azurerm` provider for both the zone and the parent NS record. If the parent zone lives in a different subscription, set the leaf's provider to that subscription, or use a provider alias and pass it via the `providers` argument from the consuming leaf.
- **RG creation is out of scope.** Place a sibling `resource-group/` leaf upstream — same convention as the AVM modules in the consuming workspace's live tree.
