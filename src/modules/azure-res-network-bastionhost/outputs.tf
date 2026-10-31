output "resource_id" {
  description = "Resource ID of the bastion host."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the bastion host."
  value       = azapi_resource.this.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the bastion host (echoes `var.resource_group_name`)."
  value       = var.resource_group_name
}

output "public_ip" {
  description = "The public IP this module created for the bastion host: `resource_id` and `name`."
  value = {
    resource_id = azapi_resource.public_ip.id
    name        = azapi_resource.public_ip.name
  }
}

output "role_assignments" {
  description = "Map of bastion-scope role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}
