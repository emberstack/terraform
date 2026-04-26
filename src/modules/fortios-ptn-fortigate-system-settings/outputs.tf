output "id" {
  description = "Terraform resource ID of the `fortios_system_global` singleton."
  value       = fortios_system_global.this.id
}

output "hostname" {
  description = "Hostname in effect on the device, read back from `fortios_system_global`."
  value       = fortios_system_global.this.hostname
}

output "admin_sport" {
  description = "HTTPS admin port in effect. Useful for building the device management URL. Reflects the device value, which is whatever it already had when `admin_sport` was left `null`."
  value       = fortios_system_global.this.admin_sport
}
