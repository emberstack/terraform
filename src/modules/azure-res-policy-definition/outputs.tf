output "resource_id" {
  description = "Resource ID of the policy definition."
  value       = azurerm_policy_definition.this.id
}

output "name" {
  description = "Policy definition name."
  value       = azurerm_policy_definition.this.name
}

output "display_name" {
  description = "Policy definition display name."
  value       = azurerm_policy_definition.this.display_name
}

output "resource" {
  description = "The full `azurerm_policy_definition` resource."
  value       = azurerm_policy_definition.this
}
