output "resource_id" {
  description = "Resource ID of the DNS forwarding ruleset."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the DNS forwarding ruleset."
  value       = azapi_resource.this.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the ruleset (echoes `var.resource_group_name`)."
  value       = var.resource_group_name
}

output "virtual_network_links" {
  description = "Map of virtual network links keyed by the input map key. Each entry exposes `resource_id`, `name` and `virtual_network_resource_id`."
  value = {
    for k, v in azapi_resource.virtual_network_links : k => {
      resource_id                 = v.id
      name                        = v.name
      virtual_network_resource_id = var.virtual_network_links[k].virtual_network_resource_id
    }
  }
}

output "role_assignments" {
  description = "Map of ruleset-scope role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}
