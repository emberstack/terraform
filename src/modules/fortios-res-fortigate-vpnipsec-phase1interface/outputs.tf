output "id" {
  description = "Terraform resource ID of the phase1 interface (its name as used by the FortiOS API)."
  value       = fortios_vpnipsec_phase1interface.this.id
}

output "name" {
  description = "Phase1 interface name: the tunnel interface that phase2s (`phase1name`), static routes (`device`) and firewall policies reference."
  value       = fortios_vpnipsec_phase1interface.this.name
}

output "interface" {
  description = "Local interface the tunnel terminates on."
  value       = fortios_vpnipsec_phase1interface.this.interface
}

output "type" {
  description = "Remote gateway type in effect (`static`, `dynamic` or `ddns`), as read back from the FortiGate."
  value       = fortios_vpnipsec_phase1interface.this.type
}
