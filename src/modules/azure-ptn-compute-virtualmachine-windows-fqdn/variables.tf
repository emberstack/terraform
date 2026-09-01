# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "virtual_machine_id" {
  type        = string
  description = "ARM resource ID of the Windows virtual machine whose in-guest primary DNS suffix this module sets."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Compute/virtualMachines/[^/]+$", var.virtual_machine_id))
    error_message = "virtual_machine_id must be an ARM resource ID of a virtual machine, e.g. /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/<name>."
  }
}

# azapi does not infer a child resource's location from its parent, so the caller
# must pass the VM's region. A run command is location-tracked and must sit in
# the same region as its VM.
variable "location" {
  type        = string
  description = "Azure region of the target VM. A run command is a location-tracked resource and must match the VM's region (e.g. westeurope)."
  nullable    = false
}

variable "dns_suffix" {
  type        = string
  description = "Primary DNS suffix to write in-guest, e.g. westeurope.cloudapp.azure.com, so the machine's FQDN matches the public DNS name of its IP. Any lowercase DNS domain is accepted."
  nullable    = false

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", var.dns_suffix))
    error_message = "dns_suffix must be a valid lowercase DNS domain (e.g. westeurope.cloudapp.azure.com)."
  }

  validation {
    condition     = length(var.dns_suffix) <= 255
    error_message = "dns_suffix must be at most 255 characters, the Windows limit for a DNS domain value."
  }
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Name of the run command resource on the VM. Change it only to avoid colliding with a run command the VM already carries."
  default     = "SetPrimaryDnsSuffix"
  nullable    = false

  # ARM documents no naming rules for runCommands (the naming-rules page has no
  # entry for them), so per the repo convention only what can be proven is
  # rejected: an empty name, and '/' — a path separator cannot appear in a
  # single URL segment.
  validation {
    condition     = length(var.name) > 0 && !strcontains(var.name, "/")
    error_message = "name must be non-empty and must not contain '/'."
  }
}

variable "reboot" {
  type        = bool
  description = "Reboot the VM (via an ARM restart) after writing the suffix so it takes effect, and block the apply until the restart completes and the VM is running again. When it's false the module only writes the registry and the suffix stays inactive until the VM is rebooted by other means."
  default     = true
  nullable    = false
}

variable "timeout_in_seconds" {
  type        = number
  description = "Script execution timeout. The script writes three registry values, so the default sits far below the platform's 90-minute default: a run that takes minutes has hung, not slowed."
  default     = 300
  nullable    = false

  validation {
    condition     = var.timeout_in_seconds > 0
    error_message = "timeout_in_seconds must be a positive number of seconds."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the run command resource."
  default     = {}
  nullable    = false
}
