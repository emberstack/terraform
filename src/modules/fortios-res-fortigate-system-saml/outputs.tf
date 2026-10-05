output "id" {
  description = "Terraform resource ID of the `fortios_system_saml` object. This is a singleton, not a per-instance identifier."
  value       = fortios_system_saml.this.id
}

output "entity_id" {
  description = "SP entity ID as read back from the FortiGate."
  value       = fortios_system_saml.this.entity_id
}

output "single_sign_on_url" {
  description = "SP assertion consumer service URL FortiOS derived from `server_address`. It must be a reply URL registered at the IdP."
  value       = fortios_system_saml.this.single_sign_on_url
}

output "single_logout_url" {
  description = "SP single logout URL FortiOS derived from `server_address`."
  value       = fortios_system_saml.this.single_logout_url
}

output "portal_url" {
  description = "SP portal URL FortiOS derived from `server_address`."
  value       = fortios_system_saml.this.portal_url
}
