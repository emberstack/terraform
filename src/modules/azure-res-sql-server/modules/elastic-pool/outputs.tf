output "resource_id" {
  description = "Resource ID of the elastic pool. Pass this to a database's `elastic_pool_resource_id`."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Elastic pool name."
  value       = azapi_resource.this.name
}

output "role_assignments" {
  description = "Map of pool-scoped role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}

output "diagnostic_settings" {
  description = "Map of diagnostic settings keyed by the input map key."
  value = {
    for k, v in azapi_resource.diagnostic_settings : k => {
      resource_id = v.id
      name        = v.name
    }
  }
}

output "lock_resource_id" {
  description = "Resource ID of the management lock on the pool. Null when `lock` is not set."
  value       = try(azapi_resource.lock[0].id, null)
}
