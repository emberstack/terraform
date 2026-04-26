output "id" {
  description = "Terraform resource ID of the FortiLink settings entry, which is its FortiOS mkey (the `name`). Use it to reference or import the entry."
  value       = fortios_switchcontroller_fortilinksettings.this.id
}

output "name" {
  description = "Name (mkey) of the FortiLink settings entry as stored on the FortiGate."
  value       = fortios_switchcontroller_fortilinksettings.this.name
}

output "fortilink" {
  description = "FortiLink interface the settings entry is bound to."
  value       = fortios_switchcontroller_fortilinksettings.this.fortilink
}
