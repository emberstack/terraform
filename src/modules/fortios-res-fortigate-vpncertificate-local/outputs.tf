output "id" {
  description = "Terraform resource ID of the local certificate (the certificate name as used by the FortiOS API)."
  value       = fortios_vpncertificate_local.this.id
}

output "name" {
  description = "Name of the local certificate. Pass this to anything that references a local certificate by name, such as `admin_server_cert` or a user `auth_cert`."
  value       = fortios_vpncertificate_local.this.name
}
