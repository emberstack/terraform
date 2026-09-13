# Computed values are read through `try` because `terraform import` does not
# apply `response_export_values` — during an import the export is simply absent,
# and a bare reference would fail the whole evaluation.

output "resource_id" {
  description = "Resource ID of the managed instance."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Managed instance name."
  value       = azapi_resource.this.name
}

output "fully_qualified_domain_name" {
  description = "Fully-qualified domain name of the instance, e.g. `example.8b3c7f1f5eff.database.windows.net`."
  value       = try(azapi_resource.this.output.fully_qualified_domain_name, null)
}

output "dns_zone" {
  description = <<-EOT
    The DNS zone partition Azure assigned to the instance - the middle label of
    the FQDN.

    Assigned at creation and fixed thereafter. Only instances sharing a zone can
    form a failover group, and this module exposes no way to pair one at create
    time - a partner has to be created by other means.
  EOT
  value       = try(azapi_resource.this.output.dns_zone, null)
}

output "system_assigned_mi_principal_id" {
  description = <<-EOT
    Principal ID of the system-assigned managed identity. Null when
    `managed_identities.system_assigned` is false.

    The `identity` block exists whenever ANY identity is attached, so on a
    user-assigned-only instance azapi reports an empty principal here rather
    than omitting it - `compact` turns that into a null a caller can test.
  EOT
  value       = try(one(compact([azapi_resource.this.identity[0].principal_id])), null)
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

    `instance_key_name` is the ARM name derived from the key URI - the handle the
    encryption protector refers to. ARM registers the key itself when the instance
    body carries `keyId`, so the registration is not a resource of this module
    and has no resource ID to expose.
  EOT
  value = var.customer_managed_key == null ? null : {
    instance_key_name       = local.instance_key_name
    encryption_protector_id = azapi_update_resource.encryption_protector[0].id
    auto_rotation_enabled   = var.customer_managed_key.auto_rotation_enabled
  }
}

output "advanced_threat_protection_resource_id" {
  description = "Resource ID of the advanced threat protection setting. Null when `advanced_threat_protection_enabled` is not set."
  value       = try(azapi_update_resource.advanced_threat_protection[0].id, null)
}

output "security_alert_policy_resource_id" {
  description = "Resource ID of the threat-detection alert policy. Null when `security_alert_policy` is not set."
  value       = try(azapi_update_resource.security_alert_policy[0].id, null)
}

output "vulnerability_assessment_resource_id" {
  description = "Resource ID of the vulnerability assessment. Null when `vulnerability_assessment` is not set."
  value       = try(azapi_update_resource.vulnerability_assessment[0].id, null)
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
  description = "Map of instance-scoped role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}

output "lock_resource_id" {
  description = "Resource ID of the management lock on the instance. Null when `lock` is not set."
  value       = try(azapi_resource.lock[0].id, null)
}
