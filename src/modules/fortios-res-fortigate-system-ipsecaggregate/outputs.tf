output "id" {
  description = "Terraform resource ID of the aggregate (its name as used by the FortiOS API)."
  value       = fortios_system_ipsecaggregate.this.id
}

output "name" {
  description = "Aggregate interface name, the one routes and policies reference."
  value       = fortios_system_ipsecaggregate.this.name
}

output "members" {
  description = "Phase1 interfaces bundled into the aggregate, sorted."
  value       = sort([for m in fortios_system_ipsecaggregate.this.member : m.tunnel_name])
}

output "algorithm" {
  description = "Traffic distribution algorithm, read back from the resource."
  value       = fortios_system_ipsecaggregate.this.algorithm
}
