# =============================================================================
# PRIVATE DNS ZONE VIRTUAL NETWORK LINKS
# =============================================================================
# Manages `azurerm_private_dns_zone_virtual_network_link` resources. Each entry
# in `var.private_dns_zone_vnet_links` becomes one link.
#
# Each entry can target a different zone — supports both single-zone (one
# leaf per zone, multiple vnets) and matrix scenarios (one leaf, many zones ×
# many vnets) without changing the module shape.
#
# The deploying principal must have write access to each link's zone RG.
# =============================================================================

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = var.private_dns_zone_vnet_links

  name                  = each.value.link_name
  resource_group_name   = split("/", each.value.private_dns_zone_resource_id)[4]
  private_dns_zone_name = split("/", each.value.private_dns_zone_resource_id)[8]
  virtual_network_id    = each.value.virtual_network_resource_id
  registration_enabled  = each.value.registration_enabled
  resolution_policy     = each.value.resolution_policy
  tags                  = merge(var.tags, each.value.tags)
}
