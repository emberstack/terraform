output "resource_id" {
  description = "Resource ID of the policy set definition (initiative)."
  value       = azurerm_policy_set_definition.this.id
}

output "name" {
  description = "Initiative name."
  value       = azurerm_policy_set_definition.this.name
}

output "display_name" {
  description = "Initiative display name."
  value       = azurerm_policy_set_definition.this.display_name
}

output "resource" {
  description = "The full `azurerm_policy_set_definition` resource."
  value       = azurerm_policy_set_definition.this
}
