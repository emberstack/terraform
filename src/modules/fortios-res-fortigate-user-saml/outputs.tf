output "id" {
  description = "Terraform resource ID of the SAML server entry (the object name as used by the FortiOS API)."
  value       = fortios_user_saml.this.id
}

output "name" {
  description = "Name of the SAML server entry. Use this to reference the server from user groups or SSL-VPN authentication rules."
  value       = fortios_user_saml.this.name
}

output "entity_id" {
  description = "Service provider entity ID configured on the FortiGate. Useful when registering the FortiGate as an application at the IdP."
  value       = fortios_user_saml.this.entity_id
}

output "idp_entity_id" {
  description = "Identity provider entity ID configured on the SAML server entry."
  value       = fortios_user_saml.this.idp_entity_id
}
