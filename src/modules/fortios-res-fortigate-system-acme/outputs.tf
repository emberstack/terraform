output "id" {
  description = "Terraform resource ID of the `fortios_system_acme` object. This is a singleton, not a per-instance identifier."
  value       = fortios_system_acme.this.id
}

output "interfaces" {
  description = "Names of the interfaces the ACME client listens on, as read back from the FortiGate."
  value       = sort([for interface in fortios_system_acme.this.interface : interface.interface_name])
}
