# Computed values are read through `try` because `terraform import` does not
# apply `response_export_values` — during an import the export is simply absent,
# and a bare reference would fail the whole evaluation.

output "resource_id" {
  description = "Resource ID of the cluster."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Cluster name."
  value       = azapi_resource.this.name
}

output "hostname" {
  description = "Fully-qualified hostname of the cluster."
  value       = try(azapi_resource.this.output.host_name, null)
}

output "system_assigned_mi_principal_id" {
  description = "Principal ID of the system-assigned managed identity, if `managed_identities.system_assigned = true`."
  value       = try(azapi_resource.this.identity[0].principal_id, null)
}

output "default_database" {
  description = "Default database — `id` and `port`."
  value = {
    id   = azapi_resource.database.id
    port = try(azapi_resource.database.output.port, null)
  }
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
  description = "Map of cluster-scoped role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      id           = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}

output "resource" {
  description = "The full cluster resource. Sensitive — prefer the focused outputs."
  sensitive   = true
  value       = azapi_resource.this
}
