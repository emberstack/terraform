output "resource_id" {
  description = "Resource ID of the public IP address."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the public IP address."
  value       = azapi_resource.this.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the public IP address (echoes `var.resource_group_name`)."
  value       = var.resource_group_name
}

output "ip_address" {
  description = "The allocated IP address. Null right after an import, until the first apply records the exported response values."
  # An import stores ARM's whole response in `output` rather than the exported
  # values, so the key is missing until the first apply.
  value = try(azapi_resource.this.output.ip_address, null)
}

output "fqdn" {
  description = "Fully qualified domain name built from `domain_name_label`, or null when no label is set."
  value       = try(azapi_resource.this.output.fqdn, null)
}

output "role_assignments" {
  description = "Map of public-IP-scope role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}
