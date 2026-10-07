variable "name" {
  description = "Zone name, at most 35 characters. Zones share one namespace with interfaces, so it cannot match an existing interface name."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 35
    error_message = "name must be 1 to 35 characters."
  }
}

variable "interfaces" {
  description = "Names of the member interfaces. Each entry becomes one `interface` block; a member must not belong to another zone or have firewall policies of its own."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.interfaces) >= 1
    error_message = "interfaces must have at least one entry."
  }
}

variable "intrazone" {
  description = "Allow or deny traffic between different members of the zone. `allow` or `deny`; `null` leaves it unmanaged; FortiOS defaults to `deny`."
  type        = string
  default     = null

  validation {
    condition     = var.intrazone == null || contains(["allow", "deny"], var.intrazone)
    error_message = "intrazone must be allow or deny."
  }
}

variable "description" {
  description = "Free-text description, at most 127 characters. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.description == null || length(var.description) <= 127
    error_message = "description must be at most 127 characters."
  }
}
