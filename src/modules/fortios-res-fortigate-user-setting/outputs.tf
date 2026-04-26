output "id" {
  description = "Terraform resource ID of the `fortios_user_setting` object. This is a singleton per VDOM, not a per-instance identifier."
  value       = fortios_user_setting.this.id
}

output "auth_cert" {
  description = "Name of the certificate configured for user authentication. Echoes `var.auth_cert` as read back from the resource."
  value       = fortios_user_setting.this.auth_cert
}
