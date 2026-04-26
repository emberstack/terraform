output "resource_id" {
  description = "Resource ID of the public DNS zone."
  value       = azurerm_dns_zone.this.id
}

output "name" {
  description = "Name of the public DNS zone."
  value       = azurerm_dns_zone.this.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the zone (echoes `var.resource_group_name`)."
  value       = var.resource_group_name
}

output "name_servers" {
  description = "Azure-assigned name servers for the zone. Use these in the parent zone's delegation (already done automatically when `parent_zone` is set)."
  value       = azurerm_dns_zone.this.name_servers
}

output "role_assignments" {
  description = "Map of zone-scope role assignments keyed by the input map key."
  value = {
    for k, v in azurerm_role_assignment.this : k => {
      id           = v.id
      principal_id = v.principal_id
    }
  }
}

output "delegation" {
  description = "Parent-zone NS delegation record details (null when `parent_zone` is not set)."
  value = var.parent_zone != null ? {
    resource_id      = azurerm_dns_ns_record.delegation[0].id
    name             = azurerm_dns_ns_record.delegation[0].name
    fqdn             = azurerm_dns_ns_record.delegation[0].fqdn
    parent_zone_id   = var.parent_zone.zone_id
    parent_zone_name = local.parent_zone_name
  } : null
}
