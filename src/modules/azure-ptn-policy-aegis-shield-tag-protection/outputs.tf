output "resource_policy_definition_id" {
  description = "Resource ID of the `Indexed`-mode policy that protects individual resources (with RG cascade)."
  value       = module.definition_resource.resource_id
}

output "resource_group_policy_definition_id" {
  description = "Resource ID of the `All`-mode policy that protects resource groups carrying the tag themselves."
  value       = module.definition_resource_group.resource_id
}

output "initiative_id" {
  description = "Resource ID of the initiative (policy set definition) bundling both policies."
  value       = module.initiative.resource_id
}

output "initiative_name" {
  description = "Name of the initiative."
  value       = module.initiative.name
}

output "assignment_id" {
  description = "Resource ID of the policy assignment."
  value       = module.assignment.resource_id
}

output "assignment_name" {
  description = "Name of the policy assignment."
  value       = module.assignment.name
}

output "scope_kind" {
  description = "Detected scope kind for the assignment."
  value       = module.assignment.scope_kind
}
