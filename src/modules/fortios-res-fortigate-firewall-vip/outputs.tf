output "id" {
  description = "Terraform resource ID of the VIP (its name as used by the FortiOS API)."
  value       = fortios_firewall_vip.this.id
}

output "name" {
  description = "VIP name, the one policies reference as a destination address."
  value       = fortios_firewall_vip.this.name
}

output "extip" {
  description = "External address or range of the VIP."
  value       = fortios_firewall_vip.this.extip
}

output "mappedip" {
  description = "Internal addresses or ranges the VIP maps to."
  value       = [for m in fortios_firewall_vip.this.mappedip : m.range]
}
