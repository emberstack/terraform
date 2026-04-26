output "id" {
  description = "Terraform resource ID of the `system dnsserver` entry, which is the interface name."
  value       = fortios_system_dnsserver.this.id
}

output "name" {
  description = "Interface the DNS server is enabled on, read back from the resource."
  value       = fortios_system_dnsserver.this.name
}

output "mode" {
  description = "Effective DNS server mode (`recursive`, `non-recursive` or `forward-only`), read back from the resource."
  value       = fortios_system_dnsserver.this.mode
}

output "dnsfilter_profile" {
  description = "Effective DNS filter profile name applied to the interface, read back from the resource. Empty when no profile is set."
  value       = fortios_system_dnsserver.this.dnsfilter_profile
}
