# Computed values are read through `try` because `terraform import` does not
# apply `response_export_values` — during an import the export is simply absent,
# and a bare reference would fail the whole evaluation.

output "resource_id" {
  description = "Resource ID of the public DNS zone."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the public DNS zone."
  value       = azapi_resource.this.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the zone (echoes `var.resource_group_name`)."
  value       = var.resource_group_name
}

output "name_servers" {
  description = "Azure-assigned name servers for the zone, sorted. Use these in the parent zone's delegation (already done automatically when `parent_zone` is set)."
  value       = local.name_servers
}

output "role_assignments" {
  description = "Map of zone-scope role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}

output "delegation" {
  description = "Parent-zone NS delegation record details (null when `parent_zone` is not set)."
  value = var.parent_zone != null ? {
    fqdn             = try(azapi_resource.delegation[0].output.fqdn, null)
    name             = azapi_resource.delegation[0].name
    parent_zone_id   = var.parent_zone.zone_id
    parent_zone_name = basename(var.parent_zone.zone_id)
    resource_id      = azapi_resource.delegation[0].id
  } : null
}
