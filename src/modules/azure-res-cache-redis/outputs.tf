output "resource_id" {
  description = "Resource ID of the cluster."
  value       = azurerm_managed_redis.this.id
}

output "name" {
  description = "Cluster name."
  value       = azurerm_managed_redis.this.name
}

output "hostname" {
  description = "Fully-qualified hostname of the cluster."
  value       = azurerm_managed_redis.this.hostname
}

output "system_assigned_mi_principal_id" {
  description = "Principal ID of the system-assigned managed identity, if `managed_identities.system_assigned = true`."
  value       = try(azurerm_managed_redis.this.identity[0].principal_id, null)
}

output "default_database" {
  description = "Default database — `id` and `port`."
  value = {
    id   = azurerm_managed_redis.this.default_database[0].id
    port = azurerm_managed_redis.this.default_database[0].port
  }
}

output "private_endpoints" {
  description = "Map of private endpoints keyed by the input map key."
  value = {
    for k, v in azurerm_private_endpoint.this : k => {
      id                 = v.id
      name               = v.name
      private_ip_address = v.private_service_connection[0].private_ip_address
      network_interface  = try(v.network_interface[0], null)
    }
  }
}

output "diagnostic_settings" {
  description = "Map of diagnostic settings keyed by the input map key."
  value = {
    for k, v in azurerm_monitor_diagnostic_setting.this : k => {
      id   = v.id
      name = v.name
    }
  }
}

output "role_assignments" {
  description = "Map of cluster-scoped role assignments keyed by the input map key."
  value = {
    for k, v in azurerm_role_assignment.this : k => {
      id           = v.id
      principal_id = v.principal_id
    }
  }
}

output "resource" {
  description = "The full `azurerm_managed_redis` resource. Sensitive — prefer the focused outputs."
  value       = azurerm_managed_redis.this
  sensitive   = true
}
