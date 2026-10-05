output "id" {
  description = "Terraform resource ID of the phase2 interface (its name as used by the FortiOS API)."
  value       = fortios_vpnipsec_phase2interface.this.id
}

output "name" {
  description = "Phase2 name."
  value       = fortios_vpnipsec_phase2interface.this.name
}

output "phase1name" {
  description = "Phase1 interface this selector belongs to."
  value       = fortios_vpnipsec_phase2interface.this.phase1name
}
