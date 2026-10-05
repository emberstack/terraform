variable "interfaces" {
  description = "Interfaces the ACME client listens on for HTTP-01 challenges. The CA must reach the FortiGate on TCP 80 at the certificate's domain through one of them. This is the complete list: an interface left out is removed."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.interfaces) > 0
    error_message = "interfaces must name at least one interface."
  }

  validation {
    condition     = alltrue([for name in var.interfaces : length(trimspace(name)) > 0])
    error_message = "interfaces must not contain empty names."
  }
}

variable "source_ip" {
  description = "Source IPv4 address for connections to the ACME server. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.source_ip == null || (can(cidrhost("${var.source_ip}/32", 0)) && can(regex("^[0-9.]+$", var.source_ip)))
    error_message = "source_ip must be an IPv4 address."
  }
}

variable "source_ip6" {
  description = "Source IPv6 address for connections to the ACME server. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.source_ip6 == null || (can(cidrhost("${var.source_ip6}/128", 0)) && strcontains(var.source_ip6, ":"))
    error_message = "source_ip6 must be an IPv6 address."
  }
}

variable "use_ha_direct" {
  description = "Reach the ACME server through the `ha-mgmt` interface when HA `ha-direct` is on. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.use_ha_direct == null || contains(["enable", "disable"], var.use_ha_direct)
    error_message = "use_ha_direct must be enable or disable."
  }
}
