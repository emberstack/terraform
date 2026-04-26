output "id" {
  description = "Terraform resource ID of the custom service (the service name). Use it for `depends_on` wiring or state addressing."
  value       = fortios_firewallservice_custom.this.id
}

output "name" {
  description = "Service name as stored on the device — the value to put in a firewall policy's `service` list."
  value       = fortios_firewallservice_custom.this.name
}

output "category" {
  description = "Service category the object was filed under."
  value       = fortios_firewallservice_custom.this.category
}

output "tcp_portrange" {
  description = "TCP port ranges as the device stores them: a single space-separated string, not the list that was passed in. Empty when no TCP ranges were configured."
  value       = fortios_firewallservice_custom.this.tcp_portrange
}

output "udp_portrange" {
  description = "UDP port ranges as the device stores them: a single space-separated string, not the list that was passed in. Empty when no UDP ranges were configured."
  value       = fortios_firewallservice_custom.this.udp_portrange
}

output "sctp_portrange" {
  description = "SCTP port ranges as the device stores them: a single space-separated string, not the list that was passed in. Empty when no SCTP ranges were configured."
  value       = fortios_firewallservice_custom.this.sctp_portrange
}
