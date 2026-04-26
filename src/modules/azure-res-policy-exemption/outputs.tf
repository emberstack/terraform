output "resource_id" {
  description = "Resource ID of the policy exemption."
  value       = local.exemption_id
}

output "name" {
  description = "Exemption name."
  value       = var.name
}

output "scope_kind" {
  description = "Detected scope kind: `management_group`, `subscription`, `resource_group`, or `resource`."
  value       = local.scope_kind
}
