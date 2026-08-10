output "resource_id" {
  description = <<-EOT
    ARM resource ID of the role definition, in the scope-independent form ARM itself returns:
    `/providers/Microsoft.Authorization/roleDefinitions/<guid>`. Use this as `role_definition_id`
    on role assignments, or append it to a scope to address the role within that scope.

    Deliberately NOT the resource's own `id`, which AzAPI builds from `parent_id` and so carries
    the anchoring management group. Both address the same role, but only this form composes.
  EOT
  value       = "/providers/Microsoft.Authorization/roleDefinitions/${azapi_resource.this.name}"
}

output "scoped_resource_id" {
  description = "The role definition addressed through its anchoring scope, as AzAPI builds it. Rarely needed — prefer `resource_id`."
  value       = azapi_resource.this.id
}

output "role_definition_id" {
  description = "GUID of the role definition (the trailing identifier in the ARM ID)."
  value       = azapi_resource.this.name
}

output "name" {
  description = "Role name."
  value       = var.name
}

output "scope" {
  description = "Scope at which the role is anchored."
  value       = var.scope
}

output "resource" {
  description = "The full role definition resource."
  value       = azapi_resource.this
}
