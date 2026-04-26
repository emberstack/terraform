# =============================================================================
# PRIVATE DNS ZONE VIRTUAL NETWORK LINK
# =============================================================================
# ONE link, managed as its own deployable unit. This is the right choice when
# each link gets its own state and its own dependency edges — the common
# Terragrunt layout of a `links/` unit sitting beside the `zone/` unit it links.
#
# For many links in a single apply — one zone to many vnets, or a many-zones ×
# many-vnets matrix — use the sibling pattern module instead:
#   azure-ptn-network-privatednszone-vnet-links
# It wraps the same resource in a `for_each` over a map. Same underlying
# resource, different unit of deployment; pick by how you want state split, not
# by capability.
#
# The parent `azure-res-network-privatednszone` module does NOT call this
# submodule — links are always managed separately from the zone so that adding
# or removing one never touches zone state.
#
# `resource_group_name` and `private_dns_zone_name` are parsed positionally out
# of the zone's ARM resource ID (segments 4 and 8) rather than taken as inputs.
# =============================================================================

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  name                  = var.name
  resource_group_name   = split("/", var.private_dns_zone_resource_id)[4]
  private_dns_zone_name = split("/", var.private_dns_zone_resource_id)[8]
  virtual_network_id    = var.virtual_network_resource_id
  registration_enabled  = var.registration_enabled
  resolution_policy     = var.resolution_policy
  tags                  = var.tags
}
