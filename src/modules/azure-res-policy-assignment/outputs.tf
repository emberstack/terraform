output "resource_id" {
  description = "Resource ID of the policy assignment."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Assignment name."
  value       = azapi_resource.this.name
}

output "scope_kind" {
  description = "Detected scope kind: `management_group`, `subscription`, `resource_group`, or `resource`. Informational only — the resource addresses every scope the same way."
  value       = local.scope_kind
}

output "system_assigned_mi_principal_id" {
  description = "Principal ID of the system-assigned identity, if `managed_identities.system_assigned = true`."
  value       = local.system_identity_principal_id
}

output "identity_role_assignments" {
  description = "Map of identity-scoped role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.identity_role_assignments : k => {
      id           = v.id
      principal_id = local.system_identity_principal_id
      scope        = v.parent_id
    }
  }
}
