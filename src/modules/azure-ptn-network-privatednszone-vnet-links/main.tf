# =============================================================================
# PRIVATE DNS ZONE VIRTUAL NETWORK LINKS
# =============================================================================
# Each entry carries its own `private_dns_zone_resource_id`, used directly as
# the link's `parent_id`. That is what lets one call span many zones — the
# many-zones × many-vnets matrix needs no special handling.
#
# The deploying principal must have write access to each link's zone RG.
# =============================================================================

resource "azapi_resource" "this" {
  for_each = var.private_dns_zone_vnet_links

  location  = "global"
  name      = each.value.link_name
  parent_id = each.value.private_dns_zone_resource_id
  type      = "Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01"
  body = {
    properties = {
      registrationEnabled = each.value.registration_enabled
      resolutionPolicy    = each.value.resolution_policy
      virtualNetwork = {
        id = each.value.virtual_network_resource_id
      }
    }
  }
  # Azure sets `resolutionPolicy` itself on privatelink zones, so a null input
  # has to mean "leave it alone" rather than "clear it". Without this every link
  # that sets no policy carries a permanent `"Default" -> null` diff.
  ignore_null_property = true
  tags                 = merge(var.tags, each.value.tags)
}
