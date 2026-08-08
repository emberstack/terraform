# Azure Private DNS Zone

Creates an Azure private DNS zone (`Microsoft.Network/privateDnsZones`) with optional SOA record customization and zone-scope IAM role assignments. Records are managed by [`azure-ptn-network-privatednszone-records`](../azure-ptn-network-privatednszone-records/); virtual-network links are managed either by [`modules/vnet-link`](./modules/vnet-link/) (one link per unit) or by [`azure-ptn-network-privatednszone-vnet-links`](../azure-ptn-network-privatednszone-vnet-links/) (many links in one apply) — see [Submodules](#submodules).

## Why this exists alongside the AVM module

The AVM module [`Azure/avm-res-network-privatednszone/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-network-privatednszone/azurerm/latest) is bundled with all concerns (zone + records + vnet links) in one module. This is fine for simple use, but breaks down for matrix scenarios (linking many zones to many vnets across tiers in one apply). It also doesn't expose SOA tuning.

This module mirrors AVM's input shape (`name`, `resource_group_name`, `tags`, `role_assignments`) and breaks records and vnet-linking out into focused sibling pattern modules — each usable standalone against any existing zone.

## Usage

### Greenfield zone with SOA, IAM

```hcl
module "vault_pl_zone" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-privatednszone?ref=vX.Y.Z"

  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = "global-dns-privatelink"
  tags                = local.tags

  role_assignments = {
    operators = {
      role_definition_id_or_name = "Private DNS Zone Contributor"
      principal_id               = data.azuread_group.dns_operators.object_id
      principal_type             = "Group"
    }
  }
}
```

### Zone + records + vnet links

```hcl
module "internal_zone" {
  source = "...//src/modules/azure-res-network-privatednszone?ref=vX.Y.Z"

  name                = "internal.acme.example"
  resource_group_name = "platform-dns"
  tags                = local.tags
}

module "internal_zone_records" {
  source = "...//src/modules/azure-ptn-network-privatednszone-records?ref=vX.Y.Z"

  private_dns_zone_resource_id = module.internal_zone.resource_id
  tags                         = local.tags

  private_dns_zone_records = {
    api = {
      name      = "api"
      type      = "A"
      ttl       = 300
      a_records = ["10.0.0.10"]
    }
  }
}

module "internal_zone_vnet_links" {
  source = "...//src/modules/azure-ptn-network-privatednszone-vnet-links?ref=vX.Y.Z"

  tags = local.tags

  private_dns_zone_vnet_links = {
    hub_vnet = {
      private_dns_zone_resource_id = module.internal_zone.resource_id
      link_name                    = "hub-vnet"
      virtual_network_resource_id  = data.azurerm_virtual_network.hub.id
      registration_enabled         = true
    }
  }
}
```

### Matrix link scenario (many zones × many vnets)

```hcl
module "privatelink_links" {
  source = "...//src/modules/azure-ptn-network-privatednszone-vnet-links?ref=vX.Y.Z"

  private_dns_zone_vnet_links = {
    for pair in flatten([
      for zone_name, zone in module.privatelink_zones : [
        for vnet_name, vnet_id in local.target_vnets : {
          key                          = "${zone_name}/${vnet_name}"
          private_dns_zone_resource_id = zone.resource_id
          link_name                    = vnet_name
          virtual_network_resource_id  = vnet_id
          registration_enabled         = false
        }
      ]
    ]) : pair.key => pair
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Submodules

- [`modules/vnet-link`](./modules/vnet-link/) — **one** `Microsoft.Network/privateDnsZones/virtualNetworkLinks`, managed as its own deployable unit.

This module never calls the submodule itself. Links are always managed separately from the zone, so adding or removing one never touches zone state.

### Choosing between `modules/vnet-link` and the collection module

Both wrap the same resource. Pick by how you want state split, not by capability:

| | [`modules/vnet-link`](./modules/vnet-link/) | [`azure-ptn-…-vnet-links`](../azure-ptn-network-privatednszone-vnet-links/) |
|---|---|---|
| Links per call | one | many (`for_each` over a map) |
| State | one unit per link | one unit for the whole set |
| Fits | a `links/` unit beside the `zone/` unit it links | one-zone-many-vnets, or a many-zones × many-vnets matrix |
| Tags | `var.tags` | `merge(var.tags, each.value.tags)` |

Per-link units cost more directories but give each link its own dependency edges and blast radius; the collection form keeps a matrix in a single apply. Both accept any existing zone — this module's output, an AVM-managed zone, or a manually-created one.

```hcl
# one link, one unit
module "link" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-privatednszone/modules/vnet-link?ref=vX.Y.Z"

  name                         = "hub"
  private_dns_zone_resource_id = module.zone.resource_id
  virtual_network_resource_id  = data.azurerm_virtual_network.hub.id
  tags                         = var.tags
}
```

## Related modules

- [`azure-ptn-network-privatednszone-records`](../azure-ptn-network-privatednszone-records/) — manage private DNS records (A, AAAA, CNAME, MX, PTR, SRV, TXT) against any existing zone. NS and CAA are not supported by Azure private DNS.
- [`azure-ptn-network-privatednszone-vnet-links`](../azure-ptn-network-privatednszone-vnet-links/) — manage `Microsoft.Network/privateDnsZones/virtualNetworkLinks` resources. Matrix-style: each entry can target a different zone and vnet. Supports both single-zone-multiple-vnets and many-zones-many-vnets in one apply.

Both pattern modules can be used standalone against any existing zone (this module's output, an AVM-managed zone, or a manually-created one).

## Requirements

- The deploying principal must have:
  - `Private DNS Zone Contributor` (or equivalent) on the resource group hosting the zone.
  - `Role Based Access Control Administrator` (or equivalent) on the zone, when `role_assignments` is set.
  - `Network Contributor` on each linked vnet's RG (for `Microsoft.Network/virtualNetworks/join/action`), when using `azure-ptn-network-privatednszone-vnet-links`.

## Notes

- **This module is `azapi`-only.** It declares `azapi` and `random`, not `azurerm`. The subscription comes
  from the configured `azapi` provider — `resource_group_name` stays a plain name, and the parent resource
  ID is assembled from the two.
- **Role definition names are resolved by a subscription-scope lookup.** AzAPI has no equivalent of
  azurerm's `role_definition_name`, so a `Microsoft.Authorization/roleDefinitions` list is read once when
  `role_assignments` is non-empty. A value that is already a resource ID bypasses the lookup.
- **SOA is a child resource.** ARM models the zone's SOA as a `privateDnsZones/SOA` record named `@`, not
  as part of the zone, so `soa_record` produces a second resource rather than an inline block.
- **Private zones are global.** No `location` input; Azure tracks zones at the subscription level, not per-region.
- **No NS or CAA records.** Azure private DNS does not support these record types — `azure-ptn-network-privatednszone-records` rejects them at validation time.
- **Cross-subscription links.** `azure-ptn-network-privatednszone-vnet-links` uses the default `azapi` provider for the link resource. The link itself lives in the zone's subscription, so cross-subscription links work as long as the deploying principal can `join/action` the target vnet (which lives in a potentially different subscription).
- **RG creation is out of scope.** Place a sibling `resource-group/` leaf upstream — same convention as the AVM modules in the consuming workspace's live tree.

## Migrating from the `azurerm` implementation

Earlier versions managed the same resources through `azurerm`. Resource *types* changed, so `moved`
blocks do not apply — Terraform reads the new addresses as unrelated resources and plans a
destroy-and-recreate. Adopt them instead, per unit:

```bash
terraform state pull > backup.tfstate
terraform state rm 'azurerm_private_dns_zone.this'
terraform state rm 'azurerm_role_assignment.this["<key>"]'
terraform import 'azapi_resource.this' '<zone-resource-id>'
terraform import 'random_uuid.role_assignment_name["<key>"]' '<existing-assignment-guid>'
terraform import 'azapi_resource.role_assignments["<key>"]' '<assignment-resource-id>'
terraform plan   # expect: No changes
```

Importing `random_uuid` with the existing assignment GUID is the step that matters. `name` falls back
to that UUID, so the adopted assignment keeps its identity; skip it and a fresh UUID is generated and
the assignment is replaced — a brief RBAC gap on apply. Supplying `role_assignments[*].name` explicitly
achieves the same thing if you would rather pin it in configuration.

Zones that set `soa_record` gain a second resource (`azapi_resource.soa[0]`) with nothing in state
behind it. Import it from `<zone-resource-id>/SOA/@` before planning.

[`modules/vnet-link`](./modules/vnet-link/) moved in the same release and needs the same treatment,
one link at a time:

```bash
terraform state rm 'module.<link>.azurerm_private_dns_zone_virtual_network_link.this'
terraform import 'module.<link>.azapi_resource.this' '<zone-resource-id>/virtualNetworkLinks/<link-name>'
```

The submodule's inputs are unchanged, so no caller configuration moves with it.
