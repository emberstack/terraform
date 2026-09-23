# Computed values are read through `try` because `terraform import` does not
# apply `response_export_values` — during an import the export is simply absent,
# and a bare reference would fail the whole evaluation.

output "resource_id" {
  description = "Resource ID of the Fabric capacity."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the Fabric capacity."
  value       = azapi_resource.this.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the capacity (echoes `var.resource_group_name`)."
  value       = var.resource_group_name
}

output "sku_name" {
  description = "Fabric F SKU of the capacity (echoes `var.sku_name`)."
  value       = var.sku_name
}

output "administration_members" {
  description = "Capacity administrators as configured, sorted. This is the desired set, not ARM's ordering of it — ARM returns the same members in an order of its own."
  value       = local.administration_members
}

output "provisioning_state" {
  description = "ARM provisioning state of the capacity (e.g. `Succeeded`). Null during an import, before the first refresh."
  value       = try(azapi_resource.this.output.provisioning_state, null)
}

output "state" {
  description = "Runtime state of the capacity (e.g. `Active`, `Paused`). Null during an import, before the first refresh."
  value       = try(azapi_resource.this.output.state, null)
}

output "role_assignments" {
  description = "Map of capacity-scope role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}
