# Computed values are read through `try` because `terraform import` does not
# apply `response_export_values` — during an import the export is simply absent,
# and a bare reference would fail the whole evaluation.

output "resource_id" {
  description = "ARM resource ID of the agent pool."
  value       = local.pool.id
}

output "name" {
  description = "The pool's ARM name. With `create_before_destroy`, this is the generated name — `name` plus a four-character suffix — and not the `name` input."
  value       = local.pool.name
}

output "provisioning_state" {
  description = "The pool's ARM provisioning state."
  value       = try(local.pool.output.provisioning_state, null)
}

output "current_orchestrator_version" {
  description = "The Kubernetes version the pool's nodes are actually running, which an upgrade channel may have moved past `orchestrator_version`."
  value       = try(local.pool.output.current_orchestrator_version, null)
}

output "node_image_version" {
  description = "The node image the pool is running. Moves on its own whenever the cluster's node OS upgrade channel rolls the pool."
  value       = try(local.pool.output.node_image_version, null)
}
