output "resource_id" {
  description = "Resource ID of the workspace."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the workspace."
  value       = azapi_resource.this.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the workspace (echoes `var.resource_group_name`)."
  value       = var.resource_group_name
}

output "system_assigned_mi_principal_id" {
  description = "Principal ID of the system-assigned managed identity, if `managed_identities.system_assigned = true`."
  value       = try(azapi_resource.this.identity[0].principal_id, null)
}

output "data_collection_rule_resource_id" {
  description = "Resource ID of the workspace transformation DCR, or null when `workspace_transforms` is not set."
  value       = try(azapi_resource.data_collection_rule[0].id, null)
}

output "role_assignments" {
  description = "Map of workspace-scope role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}
