variable "name" {
  description = "VIP name, at most 79 characters. Policies reference it as a destination address."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 79
    error_message = "name must be 1 to 79 characters."
  }
}

variable "type" {
  description = "VIP type, e.g. `static-nat` or `server-load-balance`. `null` leaves it unmanaged; FortiOS defaults to `static-nat`."
  type        = string
  default     = null
}

variable "extip" {
  description = "External address or range traffic is sent to, e.g. `198.51.100.201` or `198.51.100.201-198.51.100.202`."
  type        = string
  nullable    = false
}

variable "mappedip" {
  description = "Internal addresses or ranges the external address maps to. Each entry becomes one `mappedip` block."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.mappedip) >= 1
    error_message = "mappedip must have at least one entry."
  }
}

variable "extintf" {
  description = "Interface the VIP listens on, or `any`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "portforward" {
  description = "Translate ports as well as addresses, using `protocol`, `extport` and `mappedport`. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.portforward == null || contains(["enable", "disable"], var.portforward)
    error_message = "portforward must be enable or disable."
  }
}

variable "protocol" {
  description = "Protocol whose ports are forwarded when `portforward` is enabled, e.g. `tcp` or `udp`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "extport" {
  description = "External port or range, as FortiOS takes it (e.g. `443` or `1000-1010`). `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "mappedport" {
  description = "Internal port or range the external port maps to. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "arp_reply" {
  description = "Answer ARP requests for the external address. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.arp_reply == null || contains(["enable", "disable"], var.arp_reply)
    error_message = "arp_reply must be enable or disable."
  }
}

variable "color" {
  description = "GUI colour index (`0` = default palette entry). `null` leaves it unmanaged."
  type        = number
  default     = null
}

variable "comment" {
  description = "Free-text comment, at most 255 characters. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.comment == null || length(var.comment) <= 255
    error_message = "comment must be at most 255 characters."
  }
}
