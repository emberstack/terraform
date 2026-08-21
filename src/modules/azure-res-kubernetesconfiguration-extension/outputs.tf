# Computed values are read through `try` because `terraform import` does not
# apply `response_export_values` — during an import the export is simply absent,
# and a bare reference would fail the whole evaluation.

output "resource_id" {
  description = "Resource ID of the extension."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Extension instance name."
  value       = azapi_resource.this.name
}

output "extension_type" {
  description = "Extension type installed, as passed in."
  value       = var.extension_type
}

output "current_version" {
  description = "Version of the extension currently installed, as reported by the resource provider. Moves on its own while `auto_upgrade_minor_version` is true."
  value       = try(azapi_resource.this.output.current_version, null)
}

output "provisioning_state" {
  description = "Provisioning state of the extension, as reported by the resource provider."
  value       = try(azapi_resource.this.output.provisioning_state, null)
}

output "principal_id" {
  description = <<-EOT
    Principal ID of the extension's identity — the AKS-assigned identity where the
    resource provider creates one, otherwise the extension's own system-assigned
    identity. Null for extension types that have neither.

    Grant it roles through `identity_role_assignments`, or use this to grant them
    outside the module.
  EOT
  value       = local.extension_principal_id
}

output "identity_role_assignments" {
  description = "Map of role assignments granted to the extension's identity, keyed by the input map key."
  value = {
    for k, v in azapi_resource.identity_role_assignments : k => {
      resource_id = v.id
      scope       = v.parent_id
    }
  }
}

output "lock_resource_id" {
  description = "Resource ID of the management lock on the extension. Null when `lock` is not set."
  value       = try(azapi_resource.lock[0].id, null)
}
