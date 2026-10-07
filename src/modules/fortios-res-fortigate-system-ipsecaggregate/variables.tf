variable "name" {
  description = "Aggregate interface name, at most 15 characters. It shares the interface namespace, so it must differ from every phase1 name. ForceNew."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 15
    error_message = "name must be 1 to 15 characters."
  }
}

variable "members" {
  description = "Names of the phase1 interfaces bundled into the aggregate. Each needs `aggregate-member enable` and `net-device disable`."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.members) >= 1
    error_message = "members must name at least one phase1 interface."
  }

  validation {
    condition     = alltrue([for m in var.members : length(m) >= 1 && length(m) <= 15])
    error_message = "Every member must be a phase1 name of 1 to 15 characters."
  }

  validation {
    condition     = length(distinct(var.members)) == length(var.members)
    error_message = "members must not repeat a tunnel."
  }
}

variable "algorithm" {
  description = <<-EOT
    How traffic is spread across the members:

    - `round-robin` — per packet, alternating (the FortiOS default).
    - `weighted-round-robin` — per packet, by each member's `aggregate-weight`.
    - `L3` — per flow, by source and destination address.
    - `L4` — per flow, by addresses and ports.
    - `redundant` — everything on the first member that is up.

    `null` leaves it unmanaged.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.algorithm == null || contains(["L3", "L4", "round-robin", "redundant", "weighted-round-robin"], var.algorithm)
    error_message = "algorithm must be L3, L4, round-robin, redundant or weighted-round-robin."
  }
}
