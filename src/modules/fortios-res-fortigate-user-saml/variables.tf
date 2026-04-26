variable "name" {
  description = "Name of the SAML server entry (`config user saml`). Referenced by SSL-VPN / firewall authentication settings and by user group members."
  type        = string
}

# Service provider (FortiGate side)
variable "cert" {
  description = "Name of a local certificate already present on the FortiGate, used to sign SAML requests sent to the IdP. Empty means no signing certificate is configured."
  type        = string
  default     = ""
}

variable "entity_id" {
  description = "Service provider entity ID the FortiGate advertises to the IdP."
  type        = string
  default     = ""
}

variable "single_sign_on_url" {
  description = "Service provider assertion consumer service (ACS) URL on the FortiGate that the IdP posts the SAML response to."
  type        = string
  default     = ""
}

variable "single_logout_url" {
  description = "Service provider single logout URL on the FortiGate."
  type        = string
  default     = ""
}

variable "digest_method" {
  description = "Digest algorithm used for the SAML signature. One of `sha1` or `sha256`. Defaults to `sha256`."
  type        = string
  default     = "sha256"
}

# Identity provider (Entra / external IdP side)
variable "idp_entity_id" {
  description = "Entity ID (issuer) advertised by the identity provider."
  type        = string
  default     = ""
}

variable "idp_single_sign_on_url" {
  description = "Identity provider login URL the FortiGate redirects users to."
  type        = string
  default     = ""
}

variable "idp_single_logout_url" {
  description = "Identity provider logout URL."
  type        = string
  default     = ""
}

variable "idp_cert" {
  description = "Name of a remote certificate already installed on the FortiGate (`config vpn certificate remote`), used to verify the IdP assertion signature. This is a certificate *name*, not PEM content — see the `fortios-res-fortigate-vpncertificate-remote` module."
  type        = string
  default     = ""
}

# Attribute / claim mapping
variable "user_name" {
  description = "Name of the SAML assertion attribute (claim) that carries the username."
  type        = string
  default     = ""
}

variable "group_name" {
  description = "Name of the SAML assertion attribute (claim) that carries group membership."
  type        = string
  default     = ""
}
