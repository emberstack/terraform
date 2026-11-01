output "assignments" {
  description = <<-EOT
    Map of policy assignments keyed by the input map key — `resource_id`, `name`,
    `system_assigned_mi_principal_id` (null without a system-assigned identity)
    and `identity_role_assignments`, keyed by the nested key the caller wrote.
  EOT
  value = {
    for k, a in azapi_resource.this : k => {
      resource_id                     = a.id
      name                            = a.name
      system_assigned_mi_principal_id = var.assignments[k].managed_identities.system_assigned ? try(a.identity[0].principal_id, null) : null
      identity_role_assignments = {
        for composite_k, ra in local.identity_role_assignments : ra.ra_key => {
          resource_id = azapi_resource.identity_role_assignments[composite_k].id
          scope       = azapi_resource.identity_role_assignments[composite_k].parent_id
        }
        if ra.assignment_key == k
      }
    }
  }
}
