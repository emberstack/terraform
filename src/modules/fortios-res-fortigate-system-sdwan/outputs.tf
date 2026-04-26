output "id" {
  description = "Terraform resource ID of the SD-WAN configuration. `fortios_system_sdwan` is a singleton, so this is a fixed provider-assigned string rather than a meaningful device identifier."
  value       = fortios_system_sdwan.this.id
}

output "status" {
  description = "Whether SD-WAN is enabled on the device, read back from the resource. `enable` or `disable`."
  value       = fortios_system_sdwan.this.status
}

output "zones" {
  description = "SD-WAN zones keyed the same way as the `zones` input, each with its `name`. Echoes the input rather than reading back from the resource, so it is available at plan time for wiring zone names into firewall policies."
  value       = { for k, v in var.zones : k => { name = v.name } }
}
