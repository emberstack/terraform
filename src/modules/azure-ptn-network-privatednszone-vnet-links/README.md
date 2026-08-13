# Azure Private DNS Zone Virtual Network Links (Pattern)

Map-driven virtual network links across **many** private DNS zones and **many** virtual networks, from
one apply. Each entry names its own zone, so a single invocation can link a matrix of zones to networks.

## Why this exists alongside the AVM module

[`Azure/avm-res-network-privatednszone/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-network-privatednszone/azurerm/latest)
attaches links to the zone it creates, which ties the link's lifecycle to that one zone. The common
platform case is the reverse shape: dozens of privatelink zones owned centrally, each needing a link to
every spoke network, declared in one place.

Choose between this and the [`vnet-link`](../azure-res-network-privatednszone/modules/vnet-link/)
submodule by ownership, not by count — see
[Submodule: vnet-link](../../../docs/modules/azure.md#submodule-vnet-link).

## Usage

### Many zones, one network

```hcl
module "links" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-network-privatednszone-vnet-links?ref=vX.Y.Z"

  private_dns_zone_vnet_links = {
    blob_to_hub = {
      private_dns_zone_resource_id = module.zone_blob.resource_id
      name                         = "hub"
      virtual_network_resource_id  = var.hub_vnet_resource_id
    }

    vault_to_hub = {
      private_dns_zone_resource_id = module.zone_vault.resource_id
      name                         = "hub"
      virtual_network_resource_id  = var.hub_vnet_resource_id
    }
  }
}
```

### With auto-registration and an explicit resolution policy

```hcl
module "links" {
  source = "..."

  tags = { managed_by = "platform" }

  private_dns_zone_vnet_links = {
    internal_to_spoke = {
      private_dns_zone_resource_id = module.zone_internal.resource_id
      name                         = "spoke"
      virtual_network_resource_id  = var.spoke_vnet_resource_id
      registration_enabled         = true
    }

    privatelink_blob_to_spoke = {
      private_dns_zone_resource_id = module.zone_blob.resource_id
      name                         = "spoke"
      virtual_network_resource_id  = var.spoke_vnet_resource_id
      resolution_policy            = "NxDomainRedirect"
    }
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Notes

- **State address stability.** Each entry creates `azapi_resource.this["<key>"]`. The key is your IaC
  handle and is not part of the ARM ID — that comes from the zone plus `name` — so renaming a key
  recreates the link. Pick stable keys.
- **`registration_enabled` only applies to non-privatelink zones.** Azure rejects auto-registration on a
  privatelink zone.
- **`resolution_policy` defaults to null**, which leaves the property to Azure — it sets a value itself on
  privatelink zones. Set it explicitly only to pin one of the two accepted values, `Default` or
  `NxDomainRedirect`; the latter is a privatelink-zone-only feature.
- **Cross-subscription links work.** The link resource lives in the zone's subscription, so the module
  uses the default `azapi` provider for it. The deploying principal needs
  `Microsoft.Network/virtualNetworks/join/action` on the target network, which may sit in a different
  subscription.
- **Requirements.** `Private DNS Zone Contributor` (or equivalent) on each zone, and `Network
  Contributor` (or equivalent) on each linked network's resource group.
