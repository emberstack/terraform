# =============================================================================
# AZURE PUBLIC DNS ZONE (Microsoft.Network/dnsZones)
# =============================================================================
# Mirrors the AVM `Azure/avm-res-network-dnszone/azurerm` module's input shape
# (`name`, `resource_group_name`, `tags`, `role_assignments`) and adds two
# capabilities AVM does not yet support:
#   - SOA record customization (email, TTLs, tags)
#   - parent-zone NS delegation (creates the NS record in the parent zone)
#
# Public DNS zones are global (location-less) — no `location` input.
# =============================================================================

resource "azurerm_dns_zone" "this" {
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

  scope                                  = azurerm_dns_zone.this.id
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

# =============================================================================
# PARENT ZONE NS DELEGATION
# =============================================================================
# Creates an NS record in the parent zone to delegate this subdomain. The
# parent's RG and zone name are parsed from `parent_zone.zone_id`. The
# deploying principal must have write access to the parent zone's RG.

locals {
  parent_zone_parts = var.parent_zone != null ? split("/", var.parent_zone.zone_id) : []
  parent_zone_rg    = var.parent_zone != null ? local.parent_zone_parts[4] : null
  parent_zone_name  = var.parent_zone != null ? local.parent_zone_parts[8] : null
}

resource "azurerm_dns_ns_record" "delegation" {
  count = var.parent_zone != null ? 1 : 0

  name                = var.parent_zone.delegation_name
  zone_name           = local.parent_zone_name
  resource_group_name = local.parent_zone_rg
  ttl                 = var.parent_zone.delegation_ttl
  records             = azurerm_dns_zone.this.name_servers
  tags                = var.parent_zone.delegation_tags
}
