# =============================================================================
# PRIVATE DNS ZONE VIRTUAL NETWORK LINK
# =============================================================================
# One link per call. The parent `azure-res-network-privatednszone` module never
# calls this submodule — links stay separate from the zone so that adding or
# removing one never touches zone state. For many links in one apply, use
# `azure-ptn-network-privatednszone-vnet-links`; the README compares the two.
# =============================================================================

resource "azapi_resource" "this" {
  location  = "global"
  name      = var.name
  parent_id = var.private_dns_zone_resource_id
  type      = "Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01"
  body = {
    properties = {
      registrationEnabled = var.registration_enabled
      resolutionPolicy    = var.resolution_policy
      virtualNetwork = {
        id = var.virtual_network_resource_id
      }
    }
  }
  # Azure sets `resolutionPolicy` itself on privatelink zones, so a null input
  # has to mean "leave it alone" rather than "clear it". Without this every link
  # that sets no policy carries a permanent `"Default" -> null` diff.
  ignore_null_property = true
  tags                 = var.tags
}
