locals {
  set_definition = local.at_management_group ? one(azurerm_management_group_policy_set_definition.management_group) : one(azurerm_policy_set_definition.subscription)
}

output "resource_id" {
  description = "Resource ID of the policy set definition (initiative)."
  value       = local.set_definition.id
}

output "name" {
  description = "Initiative name."
  value       = local.set_definition.name
}

output "display_name" {
  description = "Initiative display name."
  value       = local.set_definition.display_name
}

output "resource" {
  description = "The full policy set definition resource — `azurerm_management_group_policy_set_definition` when scoped to a management group, `azurerm_policy_set_definition` otherwise. The two schemas are identical, so consumers see the same shape either way."
  value       = local.set_definition
}
