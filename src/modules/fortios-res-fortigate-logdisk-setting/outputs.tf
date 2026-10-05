output "id" {
  description = "Terraform resource ID of the `fortios_logdisk_setting` object. This is a singleton, not a per-instance identifier."
  value       = fortios_logdisk_setting.this.id
}

output "status" {
  description = "Whether local disk logging is on (`enable` or `disable`), as read back from the FortiGate."
  value       = fortios_logdisk_setting.this.status
}
