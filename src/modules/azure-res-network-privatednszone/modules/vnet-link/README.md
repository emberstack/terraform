# Private DNS Zone Virtual Network Link (Submodule)

One virtual network link on an **existing** private DNS zone. Nested submodule of
[`azure-res-network-privatednszone`](../../).

## Why this exists

The parent module creates a zone; the collection pattern
[`azure-ptn-network-privatednszone-vnet-links`](../../../azure-ptn-network-privatednszone-vnet-links/)
creates many links from one map. This submodule covers the third case: **one link, managed as its own
unit**, because the zone and the link are owned by different configurations.

Choose by ownership, not by count — see
[Submodule: vnet-link](../../../../../docs/modules/azure.md#submodule-vnet-link).

## Usage

```hcl
module "link" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-privatednszone/modules/vnet-link?ref=vX.Y.Z"

  name                         = "hub"
  private_dns_zone_resource_id = var.private_dns_zone_resource_id
  virtual_network_resource_id  = var.hub_vnet_resource_id
}
```

### With auto-registration

```hcl
module "link" {
  source = "..."

  name                         = "spoke"
  private_dns_zone_resource_id = var.private_dns_zone_resource_id
  virtual_network_resource_id  = var.spoke_vnet_resource_id
  registration_enabled         = true
  tags                         = { managed_by = "platform" }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Notes

- **`name` is part of the ARM ID.** The link is addressed as
  `<zone-resource-id>/virtualNetworkLinks/<name>`, so renaming it recreates the link — briefly removing
  DNS resolution for that network.
- **`registration_enabled` only applies to non-privatelink zones.** Azure rejects auto-registration on a
  privatelink zone.
- **`resolution_policy` defaults to null**, which leaves the property to Azure — it sets a value itself on
  privatelink zones. `Default` or `NxDomainRedirect` are the accepted values; the latter is a
  privatelink-zone-only feature. Leave it null for non-privatelink zones.
- **Requirements.** `Private DNS Zone Contributor` (or equivalent) on the zone, and
  `Microsoft.Network/virtualNetworks/join/action` on the target network — which may live in a different
  subscription, since the link itself is created in the zone's subscription.
