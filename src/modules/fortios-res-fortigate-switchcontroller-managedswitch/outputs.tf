output "id" {
  description = "Terraform resource ID of the managed switch, which is its FortiOS mkey (the `switch_id`). Use it to reference or import the switch."
  value       = fortios_switchcontroller_managedswitch.this.id
}

output "switch_id" {
  description = "Switch mkey as stored on the FortiGate. Pass this to the per-port pattern module so ports attach to the right chassis."
  value       = fortios_switchcontroller_managedswitch.this.switch_id
}

output "sn" {
  description = "Physical serial number of the FortiSwitch as stored on the FortiGate."
  value       = fortios_switchcontroller_managedswitch.this.sn
}
