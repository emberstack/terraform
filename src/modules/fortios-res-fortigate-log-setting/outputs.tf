output "id" {
  description = "Terraform resource ID of the `fortios_log_setting` object. This is a singleton per VDOM, not a per-instance identifier."
  value       = fortios_log_setting.this.id
}
