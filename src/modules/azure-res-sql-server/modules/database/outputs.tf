output "resource_id" {
  description = "Resource ID of the database."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Database name."
  value       = azapi_resource.this.name
}

output "elastic_pool_resource_id" {
  description = "Resource ID of the elastic pool this database belongs to. Null for a standalone database."
  value       = var.elastic_pool_resource_id
}

output "short_term_retention_resource_id" {
  description = "Resource ID of the point-in-time restore policy. Null when `short_term_retention` is not set, which leaves Azure's 7-day default."
  value       = try(azapi_update_resource.short_term_retention[0].id, null)
}

output "long_term_retention_resource_id" {
  description = "Resource ID of the long-term retention policy. Null when `long_term_retention` is not set - meaning no backup of this database survives deletion of its server."
  value       = try(azapi_update_resource.long_term_retention[0].id, null)
}

output "role_assignments" {
  description = "Map of database-scoped role assignments keyed by the input map key."
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
  description = "Resource ID of the management lock on the database. Null when `lock` is not set."
  value       = try(azapi_resource.lock[0].id, null)
}
