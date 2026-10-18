output "object_id" {
  description = "Object ID of the service principal — the ID role assignments, app role assignments and group memberships use."
  value       = azuread_service_principal.this.object_id
}

output "client_id" {
  description = "Client (application) ID the service principal instantiates (echoes `var.client_id`)."
  value       = azuread_service_principal.this.client_id
}

output "display_name" {
  description = "Display name, taken from the application."
  value       = azuread_service_principal.this.display_name
}

output "application_tenant_id" {
  description = "Tenant the application is registered in. For a Microsoft first-party application, a Microsoft tenant."
  value       = azuread_service_principal.this.application_tenant_id
}

output "app_role_ids" {
  description = "Map of the application's app role values to their IDs, for app role assignments against this service principal."
  value       = azuread_service_principal.this.app_role_ids
}

output "oauth2_permission_scope_ids" {
  description = "Map of the application's delegated permission scope values to their IDs."
  value       = azuread_service_principal.this.oauth2_permission_scope_ids
}
