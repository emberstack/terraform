# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "virtual_machine_id" {
  type        = string
  description = "ARM resource ID of the virtual machine whose OS disk this module patches. The disk itself is resolved from it, since the OS disk name is server-generated."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Compute/virtualMachines/[^/]+$", var.virtual_machine_id))
    error_message = "virtual_machine_id must be an ARM resource ID of a virtual machine, e.g. /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/<name>."
  }
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "public_network_access" {
  type        = string
  description = "Whether the disk image can be exported over the public endpoint. Disabled by default, which is the point of the module; new disks are created Enabled. This governs export (SAS download), not the running VM's data path."
  default     = "Disabled"
  nullable    = false

  validation {
    condition     = contains(["Enabled", "Disabled"], var.public_network_access)
    error_message = "public_network_access must be Enabled or Disabled."
  }
}

variable "network_access_policy" {
  type        = string
  description = "How the disk may be accessed over the network: AllowAll, AllowPrivate (via the disk access resource named in disk_access_id) or DenyAll. Null leaves whatever is already set, so disabling public access does not quietly reset a policy configured elsewhere."
  default     = null

  validation {
    condition     = var.network_access_policy == null || contains(["AllowAll", "AllowPrivate", "DenyAll"], var.network_access_policy)
    error_message = "network_access_policy must be AllowAll, AllowPrivate or DenyAll."
  }

  validation {
    condition     = var.network_access_policy != "AllowPrivate" || var.disk_access_id != null
    error_message = "network_access_policy AllowPrivate requires disk_access_id."
  }
}

variable "disk_access_id" {
  type        = string
  description = "ARM resource ID of the DiskAccess resource backing private-endpoint access to the disk. Only meaningful with network_access_policy AllowPrivate."
  default     = null

  validation {
    condition     = var.disk_access_id == null || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Compute/diskAccesses/[^/]+$", var.disk_access_id))
    error_message = "disk_access_id must be an ARM resource ID of a disk access, e.g. /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Compute/diskAccesses/<name>."
  }
}

variable "retry" {
  type = object({
    error_message_regex  = list(string)
    interval_seconds     = optional(number)
    max_interval_seconds = optional(number)
    multiplier           = optional(number)
    randomization_factor = optional(number)
  })
  description = "Retry the patch when the error message matches one of `error_message_regex` — a disk write can collide with an operation already running on the VM. Bounded by the Terraform context deadline. Null disables it."
  default     = null

  validation {
    condition     = var.retry == null || length(try(var.retry.error_message_regex, [])) > 0
    error_message = "retry.error_message_regex must contain at least one pattern; leave retry null to disable retrying."
  }

  # regexall, not regex: regex() errors when the pattern does not match, so
  # can(regex(p, "")) would reject every pattern not present in the empty
  # string — which is all of them.
  validation {
    condition     = var.retry == null || alltrue([for pattern in try(var.retry.error_message_regex, []) : can(regexall(pattern, ""))])
    error_message = "every retry.error_message_regex entry must be a valid regular expression."
  }
}
