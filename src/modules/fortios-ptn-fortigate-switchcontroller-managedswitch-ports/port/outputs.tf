output "id" {
  description = "Identifier of the underlying `restful_resource`, which is the per-port REST path `/cmdb/switch-controller/managed-switch/<switch_id>/ports/<port_name>`. Useful as a stable handle for the managed port or to force dependency ordering on it."
  value       = restful_resource.this.id
}
