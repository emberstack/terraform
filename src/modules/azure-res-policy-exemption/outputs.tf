output "resource_id" {
  description = "Resource ID of the policy exemption."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Exemption name."
  value       = azapi_resource.this.name
}

output "scope_kind" {
  description = "Detected scope kind: `management_group`, `subscription`, `resource_group`, or `resource`. Informational only — the resource addresses every scope the same way."
  value       = local.scope_kind
}
