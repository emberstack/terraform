variable "name" {
  description = "Phase2 name, at most 35 characters."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 35
    error_message = "name must be 1 to 35 characters."
  }
}

variable "phase1name" {
  description = "Name of the phase1 interface this selector belongs to."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.phase1name) >= 1 && length(var.phase1name) <= 15
    error_message = "phase1name must be 1 to 15 characters."
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

# -----------------------------------------------------------------------------
# Security association
# -----------------------------------------------------------------------------

variable "proposal" {
  description = "Phase2 proposals, space-separated, e.g. `aes256gcm chacha20poly1305`. Required by the provider."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.proposal)) > 0
    error_message = "proposal must not be empty."
  }
}

variable "pfs" {
  description = "Perfect forward secrecy, using `dhgrp`. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.pfs == null || contains(["enable", "disable"], var.pfs)
    error_message = "pfs must be enable or disable."
  }
}

variable "dhgrp" {
  description = "Diffie-Hellman groups for PFS, space-separated, e.g. `20 21`. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.dhgrp == null || alltrue([for group in split(" ", var.dhgrp) : contains(["1", "2", "5", "14", "15", "16", "17", "18", "19", "20", "21", "27", "28", "29", "30", "31", "32"], group)])
    error_message = "dhgrp must be space-separated groups from 1, 2, 5, 14-21 and 27-32."
  }
}

variable "replay" {
  description = "Replay detection. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.replay == null || contains(["enable", "disable"], var.replay)
    error_message = "replay must be enable or disable."
  }
}

variable "keepalive" {
  description = "Keep the SA up when idle. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.keepalive == null || contains(["enable", "disable"], var.keepalive)
    error_message = "keepalive must be enable or disable."
  }
}

variable "auto_negotiate" {
  description = "Bring the SA up without waiting for traffic. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.auto_negotiate == null || contains(["enable", "disable"], var.auto_negotiate)
    error_message = "auto_negotiate must be enable or disable."
  }
}

variable "keylife_type" {
  description = "What expires the SA: `seconds`, `kbs` or `both`. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.keylife_type == null || contains(["seconds", "kbs", "both"], var.keylife_type)
    error_message = "keylife_type must be seconds, kbs or both."
  }
}

variable "keylifeseconds" {
  description = "SA lifetime in seconds (120-172800). `null` leaves it unmanaged; FortiOS defaults to 43200."
  type        = number
  default     = null

  validation {
    condition     = var.keylifeseconds == null || (var.keylifeseconds >= 120 && var.keylifeseconds <= 172800)
    error_message = "keylifeseconds must be between 120 and 172800."
  }
}

variable "keylifekbs" {
  description = "SA lifetime in kilobytes of traffic (5120-4294967295). `null` leaves it unmanaged."
  type        = number
  default     = null

  validation {
    condition     = var.keylifekbs == null || (var.keylifekbs >= 5120 && var.keylifekbs <= 4294967295)
    error_message = "keylifekbs must be between 5120 and 4294967295."
  }
}

variable "encapsulation" {
  description = "ESP mode: `tunnel-mode` or `transport-mode`. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.encapsulation == null || contains(["tunnel-mode", "transport-mode"], var.encapsulation)
    error_message = "encapsulation must be tunnel-mode or transport-mode."
  }
}

variable "add_route" {
  description = "Add a route for the remote selector: `phase1` (follow the phase1 setting), `enable` or `disable`. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.add_route == null || contains(["phase1", "enable", "disable"], var.add_route)
    error_message = "add_route must be phase1, enable or disable."
  }
}

# -----------------------------------------------------------------------------
# Quick-mode selectors
# -----------------------------------------------------------------------------

variable "src_addr_type" {
  description = "Local selector type: `subnet`, `range`, `ip`, `name` or their IPv6 forms (`subnet6`, `range6`, `ip6`, `name6`). `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.src_addr_type == null || contains(["subnet", "range", "ip", "name", "subnet6", "range6", "ip6", "name6"], var.src_addr_type)
    error_message = "src_addr_type must be subnet, range, ip, name, subnet6, range6, ip6 or name6."
  }
}

variable "src_subnet" {
  description = "Local selector subnet as `<address> <netmask>`, with `src_addr_type = \"subnet\"`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "src_name" {
  description = "Local selector firewall address or group, with `src_addr_type = \"name\"`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "src_start_ip" {
  description = "First local selector address, with `src_addr_type` `range` or `ip`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "src_end_ip" {
  description = "Last local selector address, with `src_addr_type = \"range\"`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "src_port" {
  description = "Local selector port (1-65535, 0 for all). `null` leaves it unmanaged."
  type        = number
  default     = null

  validation {
    condition     = var.src_port == null || (var.src_port >= 0 && var.src_port <= 65535)
    error_message = "src_port must be between 0 and 65535."
  }
}

variable "dst_addr_type" {
  description = "Remote selector type: `subnet`, `range`, `ip`, `name` or their IPv6 forms (`subnet6`, `range6`, `ip6`, `name6`). `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.dst_addr_type == null || contains(["subnet", "range", "ip", "name", "subnet6", "range6", "ip6", "name6"], var.dst_addr_type)
    error_message = "dst_addr_type must be subnet, range, ip, name, subnet6, range6, ip6 or name6."
  }
}

variable "dst_subnet" {
  description = "Remote selector subnet as `<address> <netmask>`, with `dst_addr_type = \"subnet\"`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "dst_name" {
  description = "Remote selector firewall address or group, with `dst_addr_type = \"name\"`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "dst_start_ip" {
  description = "First remote selector address, with `dst_addr_type` `range` or `ip`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "dst_end_ip" {
  description = "Last remote selector address, with `dst_addr_type = \"range\"`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "dst_port" {
  description = "Remote selector port (1-65535, 0 for all). `null` leaves it unmanaged."
  type        = number
  default     = null

  validation {
    condition     = var.dst_port == null || (var.dst_port >= 0 && var.dst_port <= 65535)
    error_message = "dst_port must be between 0 and 65535."
  }
}

variable "protocol" {
  description = "Selector IP protocol number (1-255, 0 for all). `null` leaves it unmanaged."
  type        = number
  default     = null

  validation {
    condition     = var.protocol == null || (var.protocol >= 0 && var.protocol <= 255)
    error_message = "protocol must be between 0 and 255."
  }
}

# -----------------------------------------------------------------------------
# Behaviour
# -----------------------------------------------------------------------------

variable "initiator_ts_narrow" {
  description = "Let an IKEv2 initiator narrow its traffic selectors to what the responder offers. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.initiator_ts_narrow == null || contains(["enable", "disable"], var.initiator_ts_narrow)
    error_message = "initiator_ts_narrow must be enable or disable."
  }
}

variable "single_source" {
  description = "Restrict the SA to a single source address. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.single_source == null || contains(["enable", "disable"], var.single_source)
    error_message = "single_source must be enable or disable."
  }
}

variable "route_overlap" {
  description = "What to do when a selector route overlaps an existing one: `use-old`, `use-new` or `allow`. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.route_overlap == null || contains(["use-old", "use-new", "allow"], var.route_overlap)
    error_message = "route_overlap must be use-old, use-new or allow."
  }
}
