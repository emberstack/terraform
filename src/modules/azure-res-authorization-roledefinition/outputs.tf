output "resource_id" {
  description = "ARM resource ID of the role definition (without version suffix). Use this as `role_definition_id` on `azurerm_role_assignment` and friends."
  value       = azurerm_role_definition.this.role_definition_resource_id
}

output "role_definition_id" {
  description = "GUID of the role definition (the trailing identifier in the ARM ID)."
  value       = azurerm_role_definition.this.role_definition_id
}

output "name" {
  description = "Role name."
  value       = azurerm_role_definition.this.name
}

output "scope" {
  description = "Scope at which the role is anchored."
  value       = azurerm_role_definition.this.scope
}

output "resource" {
  description = "The full `azurerm_role_definition` resource."
  value       = azurerm_role_definition.this
}
