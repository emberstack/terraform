output "resource_id" {
  description = "Resource ID of the profile. The `cdn_profile_resource_id` of `modules/origin-group` and `modules/afd-endpoint`."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the profile."
  value       = azapi_resource.this.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the profile (echoes `var.resource_group_name`)."
  value       = var.resource_group_name
}

output "sku" {
  description = "Tier of the profile (echoes `var.sku`)."
  value       = var.sku
}

output "front_door_id" {
  description = "The profile's Front Door ID, sent to every origin in the `X-Azure-FDID` header — what a public origin checks to accept only this profile's traffic."
  value       = try(azapi_resource.this.output.front_door_id, null)
}

output "system_assigned_mi_principal_id" {
  description = "Principal ID of the system-assigned managed identity, if `managed_identities.system_assigned = true`."
  value       = try(azapi_resource.this.identity[0].principal_id, null)
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
  description = "Map of profile-scope role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}

output "lock_resource_id" {
  description = "Resource ID of the management lock on the profile. Null when `lock` is not set."
  value       = try(azapi_resource.lock[0].id, null)
}
