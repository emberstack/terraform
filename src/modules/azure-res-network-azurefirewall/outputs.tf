# Computed values are read through `try` because `terraform import` does not
# apply `response_export_values` — during an import the export is simply absent,
# and a bare reference would fail the whole evaluation.

output "resource_id" {
  description = "Resource ID of the firewall."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the firewall."
  value       = azapi_resource.this.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the firewall (echoes `var.resource_group_name`)."
  value       = var.resource_group_name
}

output "private_ip_address" {
  description = "The firewall's private IP in `AzureFirewallSubnet` — the next hop for user-defined routes, and the DNS server address when the policy's DNS proxy is on. Null during an import, before the first refresh."
  value = try(one([
    for config in azapi_resource.this.output.ip_configurations : config.private_ip_address
    if config.name == local.primary_ip_configuration_key
  ]), null)
}

output "firewall_policy_id" {
  description = "Resource ID of the firewall policy (echoes `var.firewall_policy_id`)."
  value       = var.firewall_policy_id
}

output "ip_configurations" {
  description = "Map of the firewall's data-plane IP configurations, keyed by the input map key: `resource_id` and `public_ip_address_resource_id`."
  value = {
    for key, config in var.ip_configurations : key => {
      resource_id                   = "${azapi_resource.this.id}/azureFirewallIpConfigurations/${key}"
      public_ip_address_resource_id = config.public_ip_address_resource_id
    }
  }
}

output "management_public_ip" {
  description = "The management public IP — `resource_id`, `name` and `ip_address` (null during an import, before the first refresh). Null when `firewall_management_ip_configuration` is not set."
  value = local.management == null ? null : {
    resource_id = azapi_resource.management_public_ip[0].id
    name        = azapi_resource.management_public_ip[0].name
    ip_address  = try(azapi_resource.management_public_ip[0].output.ip_address, null)
  }
}

output "diagnostic_settings" {
  description = "Map of diagnostic settings keyed by the input map key."
  value = {
    for k, v in azapi_resource.diagnostic_settings : k => {
      resource_id = v.id
      name        = v.name
    }
  }
}

output "role_assignments" {
  description = "Map of firewall-scope role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}

output "lock_resource_id" {
  description = "Resource ID of the management lock on the firewall. Null when `lock` is not set."
  value       = try(azapi_resource.lock[0].id, null)
}
