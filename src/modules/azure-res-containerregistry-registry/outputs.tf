output "resource_id" {
  description = "Resource ID of the registry."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Registry name."
  value       = azapi_resource.this.name
}

output "resource_group_name" {
  description = "Name of the resource group the registry is in."
  value       = var.resource_group_name
}

output "system_assigned_mi_principal_id" {
  description = "Principal ID of the system-assigned managed identity, if `managed_identities.system_assigned = true`."
  value       = try(azapi_resource.this.identity[0].principal_id, null)
}

output "georeplications" {
  description = "Map of geo-replicas keyed by region — `resource_id`."
  value = {
    for k, v in azapi_resource.replications : k => {
      resource_id = v.id
    }
  }
}

output "private_endpoints" {
  description = <<-EOT
    Map of private endpoints keyed by the input map key.

    `role_assignments` nests each endpoint's own assignments, keyed by the nested key the
    caller wrote — not by the composite `<endpoint>-<assignment>` key used to address them
    in state. `lock_resource_id` is null on an endpoint that sets no `lock`.
  EOT
  value = {
    for k, v in azapi_resource.private_endpoint : k => {
      resource_id = v.id
      name        = v.name
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
  description = "Map of registry-scoped role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}

output "lock_resource_id" {
  description = "Resource ID of the management lock on the registry. Null when `lock` is not set."
  value       = try(azapi_resource.lock[0].id, null)
}
