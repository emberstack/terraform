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
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-dnszone?ref=vX.Y.Z"

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

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Related modules

- [`azure-ptn-network-dnszone-records`](../azure-ptn-network-dnszone-records/) — manage DNS records (A, AAAA, CNAME, MX, NS, PTR, SRV, TXT, CAA) against any existing zone (this module's output, an AVM-managed zone, or a manually-created one).

### Adding records to the zone

```hcl
module "dev_zone" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-dnszone?ref=vX.Y.Z"

  name                = "dev.acme.example"
  resource_group_name = "dev-platform-dns"
  tags                = local.tags
}

module "dev_zone_records" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-network-dnszone-records?ref=vX.Y.Z"

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

- The deploying principal must have:
  - `DNS Zone Contributor` (or equivalent) on the resource group hosting the zone.
  - `DNS Zone Contributor` (or equivalent) on the **parent zone's** resource group, when `parent_zone` is set.
  - `Role Based Access Control Administrator` (or equivalent) on the zone, when `role_assignments` is set.

## Notes

- **Public zones are global.** No `location` input; Azure tracks zones at the subscription level, not per-region.
- **Parent zone in a different subscription.** This module uses the default `azurerm` provider for both the zone and the parent NS record. If the parent zone lives in a different subscription, set the leaf's provider to that subscription, or use a provider alias and pass it via the `providers` argument from the consuming leaf.
- **RG creation is out of scope.** Place a sibling `resource-group/` leaf upstream — same convention as the AVM modules in the consuming workspace's live tree.
