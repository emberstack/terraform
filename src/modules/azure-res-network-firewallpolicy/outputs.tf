output "resource_id" {
  description = "Resource ID of the firewall policy — the `firewall_policy_id` for `azure-res-network-azurefirewall`, and the `firewall_policy_resource_id` for `modules/rule-collection-group`."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the firewall policy."
  value       = azapi_resource.this.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the policy (echoes `var.resource_group_name`)."
  value       = var.resource_group_name
}

output "role_assignments" {
  description = "Map of policy-scope role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}

output "lock_resource_id" {
  description = "Resource ID of the management lock on the policy. Null when `lock` is not set."
  value       = try(azapi_resource.lock[0].id, null)
}
