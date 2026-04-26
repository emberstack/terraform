output "id" {
  description = "Terraform resource ID of the NAC policy, which is its `name`."
  value       = fortios_user_nacpolicy.this.id
}

output "name" {
  description = "Name of the NAC policy, for referencing it from other FortiOS resources."
  value       = fortios_user_nacpolicy.this.name
}
