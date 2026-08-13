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
  description = "Default database — `resource_id` and `port`."
  value = {
    resource_id = azapi_resource.database.id
    port        = try(azapi_resource.database.output.port, null)
  }
}

output "private_endpoints" {
  description = <<-EOT
    Map of private endpoints keyed by the input map key.

    `private_ip_address` is not carried on the endpoint itself — ARM surfaces the allocated
    address through the DNS zone group's record sets, falling back to `customDnsConfigs`. It
    is null until the endpoint has been created and, without a DNS zone group, may stay null.

    `role_assignments` nests each endpoint's own assignments, keyed by the nested key the
    caller wrote — not by the composite `<endpoint>-<assignment>` key used to address them
    in state. `lock_resource_id` is null on an endpoint that sets no `lock`.
  EOT
  value = {
    for k, v in azapi_resource.private_endpoint : k => {
      resource_id       = v.id
      name              = v.name
      network_interface = try(v.output.network_interfaces[0], null)
      private_ip_address = try(
        flatten([for record in azapi_resource.private_endpoint_dns_zone_group[k].output.record_sets : record.ipAddresses])[0],
        v.output.custom_dns_configs[0].ipAddresses[0],
        null
      )
      # `private_endpoint_lock` only has an instance for endpoints that set `lock`,
      # so an absent key here means "no lock", not an error.
      lock_resource_id = try(azapi_resource.private_endpoint_lock[k].id, null)
      role_assignments = {
        for composite_k, ra in local.private_endpoint_role_assignments : ra.ra_key => {
          resource_id  = azapi_resource.private_endpoint_role_assignments[composite_k].id
          principal_id = ra.principal_id
        }
        if ra.pe_key == k
      }
    }
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
  description = "Map of cluster-scoped role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}

output "lock_resource_id" {
  description = "Resource ID of the management lock on the cluster. Null when `lock` is not set."
  value       = try(azapi_resource.lock[0].id, null)
}
