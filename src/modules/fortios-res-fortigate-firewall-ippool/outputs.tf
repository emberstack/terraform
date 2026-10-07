output "id" {
  description = "Terraform resource ID of the IP pool (its name as used by the FortiOS API)."
  value       = fortios_firewall_ippool.this.id
}

output "name" {
  description = "IP pool name, the one policies reference in `poolname`."
  value       = fortios_firewall_ippool.this.name
}

output "startip" {
  description = "First address of the pool."
  value       = fortios_firewall_ippool.this.startip
}

output "endip" {
  description = "Last address of the pool."
  value       = fortios_firewall_ippool.this.endip
}
