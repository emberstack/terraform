variable "name" {
  description = "IP pool name, at most 79 characters."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 79
    error_message = "name must be 1 to 79 characters."
  }
}

variable "type" {
  description = "Pool type, e.g. `overload` (many sources share the pool addresses through port translation) or `one-to-one`. `null` leaves it unmanaged; FortiOS defaults to `overload`."
  type        = string
  default     = null
}

variable "startip" {
  description = "First IPv4 address of the pool."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", var.startip)) && can(cidrhost("${var.startip}/32", 0))
    error_message = "startip must be an IPv4 address."
  }
}

variable "endip" {
  description = "Last IPv4 address of the pool. Equal to `startip` for a single-address pool."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", var.endip)) && can(cidrhost("${var.endip}/32", 0))
    error_message = "endip must be an IPv4 address."
  }
}

variable "arp_reply" {
  description = "Answer ARP requests for the pool addresses. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.arp_reply == null || contains(["enable", "disable"], var.arp_reply)
    error_message = "arp_reply must be enable or disable."
  }
}

variable "comments" {
  description = "Free-text comment, at most 255 characters. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.comments == null || length(var.comments) <= 255
    error_message = "comments must be at most 255 characters."
  }
}
