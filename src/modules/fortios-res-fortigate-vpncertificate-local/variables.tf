variable "name" {
  description = "Name of the local certificate (`config vpn certificate local`), at most 35 characters. Other objects reference it by this name, e.g. `admin_server_cert`. Changing it replaces the certificate."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 35
    error_message = "name must be 1 to 35 characters."
  }
}

variable "comments" {
  description = "Free-text comment on the certificate, at most 511 characters. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.comments == null || length(var.comments) <= 511
    error_message = "comments must be at most 511 characters."
  }
}

variable "acme" {
  description = <<-EOT
    ACME enrollment. Unset optional fields are not sent, so FortiOS applies its
    own defaults.

    - `domain`       — the domain the certificate is issued for. It must
                       resolve publicly to the FortiGate.
    - `email`        — contact address registered with the CA.
    - `ca_url`       — ACME directory URL. FortiOS defaults to Let's Encrypt
                       production (`https://acme-v02.api.letsencrypt.org/directory`).
    - `rsa_key_size` — 2048 to 4096. FortiOS defaults to 2048.
    - `renew_window` — days before expiry to renew, 1 to 60. FortiOS defaults
                       to 30.
    - `eab_key_id`   — External Account Binding key ID, for CAs that require
                       it. The matching HMAC goes in `acme_eab_key_hmac`.
  EOT
  type = object({
    domain       = string
    email        = optional(string)
    ca_url       = optional(string)
    rsa_key_size = optional(number)
    renew_window = optional(number)
    eab_key_id   = optional(string)
  })
  nullable = false

  validation {
    condition     = length(var.acme.domain) >= 1 && length(var.acme.domain) <= 255
    error_message = "acme.domain must be 1 to 255 characters."
  }

  validation {
    condition     = var.acme.ca_url == null || can(regex("^https://", var.acme.ca_url))
    error_message = "acme.ca_url must be an https:// URL."
  }

  validation {
    condition     = var.acme.rsa_key_size == null || (var.acme.rsa_key_size >= 2048 && var.acme.rsa_key_size <= 4096)
    error_message = "acme.rsa_key_size must be between 2048 and 4096."
  }

  validation {
    condition     = var.acme.renew_window == null || (var.acme.renew_window >= 1 && var.acme.renew_window <= 60)
    error_message = "acme.renew_window must be between 1 and 60."
  }
}

variable "acme_eab_key_hmac" {
  description = "External Account Binding HMAC key, paired with `acme.eab_key_id`. Kept out of `acme` so only this value is marked sensitive. `null` sends none."
  type        = string
  default     = null
  sensitive   = true
}
