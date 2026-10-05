variable "name" {
  description = "Name of the user group, at most 35 characters. Firewall policies and VPN tunnels reference the group by this name."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 35
    error_message = "name must be 1 to 35 characters."
  }
}

variable "group_type" {
  description = "Kind of group: `firewall` (users and remote servers authenticating through policies or VPNs), `fsso-service`, `rsso`, `guest` or `scim`. `null` leaves it unmanaged; FortiOS defaults to `firewall`."
  type        = string
  default     = null

  validation {
    condition     = var.group_type == null || contains(["firewall", "fsso-service", "rsso", "guest", "scim"], var.group_type)
    error_message = "group_type must be one of firewall, fsso-service, rsso, guest or scim."
  }
}

variable "authtimeout" {
  description = "Authentication timeout for this group, in minutes (0-43200). 0 uses the global `user setting` auth-timeout. `null` leaves it unmanaged."
  type        = number
  default     = null

  validation {
    condition     = var.authtimeout == null || (var.authtimeout >= 0 && var.authtimeout <= 43200)
    error_message = "authtimeout must be between 0 and 43200."
  }
}

variable "members" {
  description = "Names of the group's members: local users, peers, or remote authentication servers (LDAP, RADIUS, SAML). This is the complete list: a member left out is removed."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for name in var.members : length(trimspace(name)) > 0])
    error_message = "members must not contain empty names."
  }
}

variable "matches" {
  description = <<-EOT
    Narrows a remote server member to the users of one of its groups. Each
    entry is `{ server_name, group_name }`: the remote server (normally also
    listed in `members`) and the group as the server reports it — for SAML the
    value of the group attribute, e.g. an Entra group object ID. Empty lets
    every user the server authenticates into the group.
  EOT
  type = list(object({
    server_name = string
    group_name  = string
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for match in var.matches : length(match.server_name) >= 1 && length(match.server_name) <= 35])
    error_message = "Each matches[].server_name must be 1 to 35 characters."
  }

  validation {
    condition     = alltrue([for match in var.matches : length(match.group_name) >= 1 && length(match.group_name) <= 511])
    error_message = "Each matches[].group_name must be 1 to 511 characters."
  }
}
