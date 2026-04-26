output "id" {
  description = "Numeric DHCP server ID assigned by FortiOS (`fosid`). Use it to reference this server from other FortiOS configuration."
  value       = fortios_systemdhcp_server.this.fosid
}

output "interface" {
  description = "Name of the system interface the DHCP server is bound to, read back from the resource."
  value       = fortios_systemdhcp_server.this.interface
}
