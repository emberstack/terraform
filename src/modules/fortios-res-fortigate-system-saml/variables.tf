variable "status" {
  description = "Administrator SAML SSO. `enable` or `disable`."
  type        = string
  default     = "enable"
  nullable    = false

  validation {
    condition     = contains(["enable", "disable"], var.status)
    error_message = "status must be enable or disable."
  }
}

# -----------------------------------------------------------------------------
# Service provider (the FortiGate)
# -----------------------------------------------------------------------------

variable "server_address" {
  description = "Address the IdP sends admins back to, as `host` or `host:port` (at most 63 characters) — the admin GUI's FQDN and HTTPS admin port. FortiOS builds the SP endpoints (`/saml/?acs`, `/saml/?sls`) from it."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.server_address) >= 1 && length(var.server_address) <= 63
    error_message = "server_address must be 1 to 63 characters."
  }
}

variable "entity_id" {
  description = "SP entity ID, at most 255 characters. It must match the identifier registered for the FortiGate at the IdP, typically `https://<server_address>/saml/metadata`."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.entity_id) >= 1 && length(var.entity_id) <= 255
    error_message = "entity_id must be 1 to 255 characters."
  }
}

variable "cert" {
  description = "Name of the local certificate that signs SAML messages, at most 35 characters. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.cert == null || (length(var.cert) >= 1 && length(var.cert) <= 35)
    error_message = "cert must be 1 to 35 characters."
  }
}

variable "binding_protocol" {
  description = "Binding used to send the authentication request to the IdP: `post` or `redirect`. `null` leaves it unmanaged; FortiOS defaults to `redirect`."
  type        = string
  default     = null

  validation {
    condition     = var.binding_protocol == null || contains(["post", "redirect"], var.binding_protocol)
    error_message = "binding_protocol must be post or redirect."
  }
}

variable "default_login_page" {
  description = "Login page shown by default: `normal` (local credentials, with an SSO button) or `sso` (straight to the IdP). `null` leaves it unmanaged; FortiOS defaults to `normal`."
  type        = string
  default     = null

  validation {
    condition     = var.default_login_page == null || contains(["normal", "sso"], var.default_login_page)
    error_message = "default_login_page must be normal or sso."
  }
}

variable "default_profile" {
  description = "Admin profile given on first login to an SSO admin with no `system sso-admin` entry, at most 35 characters. Anyone the IdP lets through gets it, so restrict access at the IdP, or set `admin_no_access` to admit only pre-created SSO admins. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.default_profile == null || (length(var.default_profile) >= 1 && length(var.default_profile) <= 35)
    error_message = "default_profile must be 1 to 35 characters."
  }
}

# -----------------------------------------------------------------------------
# Identity provider
# -----------------------------------------------------------------------------

variable "idp_entity_id" {
  description = "IdP entity ID (issuer), e.g. `https://sts.windows.net/<tenant-id>/` for Entra ID."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.idp_entity_id) > 0
    error_message = "idp_entity_id must not be empty."
  }
}

variable "idp_single_sign_on_url" {
  description = "IdP single sign-on URL the FortiGate sends authentication requests to."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^https://", var.idp_single_sign_on_url))
    error_message = "idp_single_sign_on_url must be an https:// URL."
  }
}

variable "idp_single_logout_url" {
  description = "IdP single logout URL. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.idp_single_logout_url == null || can(regex("^https://", var.idp_single_logout_url))
    error_message = "idp_single_logout_url must be an https:// URL."
  }
}

variable "idp_cert" {
  description = "Name of the remote certificate holding the IdP's signing certificate, e.g. created with `fortios-res-fortigate-vpncertificate-remote`."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.idp_cert) > 0
    error_message = "idp_cert must not be empty."
  }
}

# -----------------------------------------------------------------------------
# Assertion validation
# -----------------------------------------------------------------------------

variable "require_signed_resp_and_asrt" {
  description = "Require the IdP to sign both the response and the assertion. `enable` or `disable`; `null` leaves it unmanaged. FortiOS defaults to `disable`."
  type        = string
  default     = null

  validation {
    condition     = var.require_signed_resp_and_asrt == null || contains(["enable", "disable"], var.require_signed_resp_and_asrt)
    error_message = "require_signed_resp_and_asrt must be enable or disable."
  }
}

variable "tolerance" {
  description = "Clock skew allowed when checking the assertion's validity window, in minutes. `null` leaves it unmanaged; FortiOS defaults to 5."
  type        = number
  default     = null

  validation {
    condition     = var.tolerance == null || var.tolerance >= 0
    error_message = "tolerance must not be negative."
  }
}

variable "life" {
  description = "Length of the assertion's validity window, in minutes. `null` leaves it unmanaged; FortiOS defaults to 30."
  type        = number
  default     = null

  validation {
    condition     = var.life == null || var.life >= 0
    error_message = "life must not be negative."
  }
}
