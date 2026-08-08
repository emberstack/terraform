output "resource_id" {
  description = "Resource ID of the private DNS zone."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the private DNS zone."
  value       = azapi_resource.this.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the zone (echoes `var.resource_group_name`)."
  value       = var.resource_group_name
}

output "role_assignments" {
  description = "Map of zone-scope role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      id           = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}
