output "id" {
  description = "Resource ID of the DNS zone as tracked by the provider. Matches the zone mkey (`name`)."
  value       = fortios_system_dnsdatabase.this.id
}

output "name" {
  description = "Zone mkey as stored on the FortiGate. Use it to reference the zone from other configuration."
  value       = fortios_system_dnsdatabase.this.name
}

output "domain" {
  description = "DNS domain name the zone is authoritative for, as read back from the FortiGate."
  value       = fortios_system_dnsdatabase.this.domain
}
