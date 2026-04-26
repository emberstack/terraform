output "resource_id" {
  description = "Resource ID of the private DNS zone."
  value       = azurerm_private_dns_zone.this.id
}

output "name" {
  description = "Name of the private DNS zone."
  value       = azurerm_private_dns_zone.this.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the zone (echoes `var.resource_group_name`)."
  value       = var.resource_group_name
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
