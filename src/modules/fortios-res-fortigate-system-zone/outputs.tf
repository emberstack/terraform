output "id" {
  description = "Terraform resource ID of the zone (its name as used by the FortiOS API)."
  value       = fortios_system_zone.this.id
}

output "name" {
  description = "Zone name, the one policies reference as `srcintf` or `dstintf`."
  value       = fortios_system_zone.this.name
}

output "interfaces" {
  description = "Names of the member interfaces."
  value       = sort([for i in fortios_system_zone.this.interface : i.interface_name])
}
