# Computed values are read through `try` because `terraform import` does not
# apply `response_export_values` — during an import the export is simply absent,
# and a bare reference would fail the whole evaluation.

output "resource_id" {
  description = "Resource ID of the SignalR Service."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the SignalR Service."
  value       = azapi_resource.this.name
}

output "hostname" {
  description = "Fully-qualified hostname of the SignalR Service."
  value       = try(azapi_resource.this.output.host_name, null)
}

output "public_port" {
  description = "Public port the service listens on."
  value       = try(azapi_resource.this.output.public_port, null)
}

output "server_port" {
  description = "Server port the service listens on."
  value       = try(azapi_resource.this.output.server_port, null)
}

output "system_assigned_mi_principal_id" {
  description = "Principal ID of the system-assigned managed identity, if `managed_identities.system_assigned = true`."
  value       = try(azapi_resource.this.identity[0].principal_id, null)
}

output "access_keys" {
  description = <<-EOT
    Primary and secondary access keys and connection strings.

    Null unless `include_access_keys = true` — the keys are fetched with a separate `listKeys`
    call that is skipped by default. Also inert when `local_auth_enabled = false`.
  EOT
  sensitive   = true
  value = var.include_access_keys ? {
    primary_connection_string   = try(azapi_resource_action.access_keys[0].output.primaryConnectionString, null)
    primary_key                 = try(azapi_resource_action.access_keys[0].output.primaryKey, null)
    secondary_connection_string = try(azapi_resource_action.access_keys[0].output.secondaryConnectionString, null)
    secondary_key               = try(azapi_resource_action.access_keys[0].output.secondaryKey, null)
  } : null
}

output "private_endpoints" {
  description = <<-EOT
    Map of private endpoints keyed by the input map key.

    `private_ip_address` is not carried on the endpoint itself — ARM surfaces the allocated
    address through the DNS zone group's record sets, falling back to `customDnsConfigs`. It
    is null until the endpoint has been created and, without a DNS zone group, may stay null.
  EOT
  value = {
    for k, v in azapi_resource.private_endpoint : k => {
      id                = v.id
      name              = v.name
      network_interface = try(v.output.network_interfaces[0], null)
      private_ip_address = try(
        flatten([for record in azapi_resource.private_endpoint_dns_zone_group[k].output.record_sets : record.ipAddresses])[0],
        v.output.custom_dns_configs[0].ipAddresses[0],
        null
      )
    }
  }
}

output "diagnostic_settings" {
  description = "Map of diagnostic settings keyed by the input map key."
  value = {
    for k, v in azapi_resource.diagnostic_settings : k => {
      id   = v.id
      name = v.name
    }
  }
}

output "role_assignments" {
  description = "Map of service-scoped role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      id           = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}

output "resource" {
  description = "The full SignalR Service resource. Sensitive — prefer the focused outputs."
  sensitive   = true
  value       = azapi_resource.this
}
