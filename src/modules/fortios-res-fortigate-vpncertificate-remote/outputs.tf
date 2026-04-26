output "id" {
  description = "Terraform resource ID of the remote certificate entry (the certificate name as used by the FortiOS API)."
  value       = fortios_vpncertificate_remote.this.id
}

output "name" {
  description = "Name of the remote certificate entry. Pass this to anything that references a remote certificate by name, such as `idp_cert` on a SAML server."
  value       = fortios_vpncertificate_remote.this.name
}
