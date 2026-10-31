output "resource_id" {
  description = "Resource ID of the WAF policy, spelled as ARM spells it (`applicationGatewayWebApplicationFirewallPolicies`)."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the WAF policy."
  value       = azapi_resource.this.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the WAF policy (echoes `var.resource_group_name`)."
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
