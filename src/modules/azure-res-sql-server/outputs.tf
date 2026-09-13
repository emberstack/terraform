# Computed values are read through `try` because `terraform import` does not
# apply `response_export_values` — during an import the export is simply absent,
# and a bare reference would fail the whole evaluation.

output "resource_id" {
  description = "Resource ID of the server."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Server name."
  value       = azapi_resource.this.name
}

output "fully_qualified_domain_name" {
  description = "Fully-qualified domain name of the server, e.g. `example.database.windows.net`."
  value       = try(azapi_resource.this.output.fully_qualified_domain_name, null)
}

output "system_assigned_mi_principal_id" {
  description = "Principal ID of the system-assigned managed identity, if `managed_identities.system_assigned = true`."
  value       = try(azapi_resource.this.identity[0].principal_id, null)
}

output "entra_administrator_resource_id" {
  description = "Resource ID of the Entra administrator. Null when `entra_administrator` is not set."
  value       = try(azapi_resource.administrator[0].id, null)
}

output "entra_only_authentication_resource_id" {
  description = "Resource ID of the Entra-only authentication setting. Null when `entra_only_authentication_enabled` is not set."
  value       = try(azapi_update_resource.entra_only_authentication[0].id, null)
}

output "customer_managed_key" {
  description = <<-EOT
    Transparent Data Encryption key registration. Null when `customer_managed_key`
    is not set.

    `server_key_name` is the ARM name derived from the key URI - the handle the
    encryption protector refers to. ARM registers the key itself when the server
    body carries `keyId`, so the registration is not a resource of this module
    and has no resource ID to expose.
  EOT
  value = var.customer_managed_key == null ? null : {
    server_key_name         = local.server_key_name
    encryption_protector_id = azapi_update_resource.encryption_protector[0].id
    auto_rotation_enabled   = var.customer_managed_key.auto_rotation_enabled
  }
}

output "connection_policy_resource_id" {
  description = "Resource ID of the connection policy. Null when `connection_policy` is not set."
  value       = try(azapi_update_resource.connection_policy[0].id, null)
}

output "auditing_resource_id" {
  description = "Resource ID of the server auditing policy. Null when `auditing` is not set."
  value       = try(azapi_update_resource.auditing[0].id, null)
}

output "firewall_rules" {
  description = "Map of firewall rules keyed by the input map key."
  value = {
    for k, v in azapi_resource.firewall_rules : k => {
      resource_id = v.id
      name        = v.name
    }
  }
}

output "virtual_network_rules" {
  description = "Map of virtual network rules keyed by the input map key."
  value = {
    for k, v in azapi_resource.virtual_network_rules : k => {
      resource_id = v.id
      name        = v.name
    }
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
  description = "Map of server-scoped role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}

output "lock_resource_id" {
  description = "Resource ID of the management lock on the server. Null when `lock` is not set."
  value       = try(azapi_resource.lock[0].id, null)
}
