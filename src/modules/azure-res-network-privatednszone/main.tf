# =============================================================================
# AZURE PRIVATE DNS ZONE (Microsoft.Network/privateDnsZones)
# =============================================================================
# Manages the zone resource, optional SOA record overrides, and zone-scope
# role assignments. Records are managed by the sibling
# `azure-ptn-network-privatednszone-records` pattern module.
#
# Virtual-network links are deliberately NOT managed here, so that adding or
# removing a link never touches zone state. Two options, same resource:
#   - `modules/vnet-link` — one link as its own deployable unit
#   - `azure-ptn-network-privatednszone-vnet-links` — many links in one apply
# See the README's "Submodules" section for how to choose.
#
# Private DNS zones are global (location-less) — no `location` input.
# =============================================================================

resource "azurerm_private_dns_zone" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  tags                = var.tags

  dynamic "soa_record" {
    for_each = var.soa_record != null ? [var.soa_record] : []
    content {
      email        = soa_record.value.email
      expire_time  = soa_record.value.expire_time
      minimum_ttl  = soa_record.value.minimum_ttl
      refresh_time = soa_record.value.refresh_time
      retry_time   = soa_record.value.retry_time
      ttl          = soa_record.value.ttl
      tags         = soa_record.value.tags
    }
  }
}

# =============================================================================
# ROLE ASSIGNMENTS (zone scope)
# =============================================================================

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope                                  = azurerm_private_dns_zone.this.id
  role_definition_id                     = startswith(lower(each.value.role_definition_id_or_name), "/subscriptions") ? each.value.role_definition_id_or_name : null
  role_definition_name                   = startswith(lower(each.value.role_definition_id_or_name), "/subscriptions") ? null : each.value.role_definition_id_or_name
  principal_id                           = each.value.principal_id
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  description                            = each.value.description
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
  principal_type                         = each.value.principal_type
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
}
