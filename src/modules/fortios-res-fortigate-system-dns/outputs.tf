output "id" {
  description = "Resource ID of the global DNS setting. `system/dns` is a singleton, so this is a fixed identifier rather than a per-object key."
  value       = fortios_system_dns.this.id
}

output "primary" {
  description = "Primary DNS server IP as read back from the FortiGate."
  value       = fortios_system_dns.this.primary
}

output "secondary" {
  description = "Secondary DNS server IP as read back from the FortiGate. Empty when none is configured."
  value       = fortios_system_dns.this.secondary
}

output "protocol" {
  description = "DNS transport in effect on the FortiGate (`cleartext`, `dot` or `doh`)."
  value       = fortios_system_dns.this.protocol
}
