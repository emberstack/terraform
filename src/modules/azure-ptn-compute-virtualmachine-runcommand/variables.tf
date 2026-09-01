# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "virtual_machine_id" {
  type        = string
  description = "ARM resource ID of the virtual machine to run the script on."
  nullable    = false

  # VM only. A scale set instance takes runCommands too, but under a different
  # parent path (virtualMachineScaleSets/.../virtualMachines/{id}), so it would
  # need its own module rather than a looser pattern here.
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

variable "name" {
  type        = string
  description = "Name of the run command resource on the VM. It is the resource's identity, so it must be unique among the run commands that VM already carries, and changing it replaces the resource — which is also the only way to re-run unchanged content."
  nullable    = false

  # ARM documents no naming rules for runCommands (the naming-rules page has no
  # entry for them), so only what can be proven is rejected: an empty name, and
  # '/' — a path separator cannot appear in a single URL segment.
  validation {
    condition     = length(var.name) > 0 && !strcontains(var.name, "/")
    error_message = "name must be non-empty and must not contain '/'."
  }
}

# -----------------------------------------------------------------------------
# Source — exactly one
# -----------------------------------------------------------------------------
# ARM accepts only one source input per execution. The exactly-one rule is
# checked on `script` below; it is a cross-variable condition, so it reports
# there no matter which of the three the caller got wrong.

variable "script" {
  type        = string
  description = "Script content to run in the guest, inline. PowerShell on Windows, shell on Linux. Mutually exclusive with script_uri and command_id."
  default     = null

  validation {
    condition     = length([for s in [var.script, var.script_uri, var.command_id] : s if s != null]) == 1
    error_message = "Exactly one of script, script_uri or command_id must be set."
  }

  validation {
    condition     = var.script == null || length(var.script) > 0
    error_message = "script must not be empty when set; leave it null to use another source."
  }
}

variable "script_uri" {
  type        = string
  description = "Download location of the script: a storage blob SAS URI with read access, or a public URI. Mutually exclusive with script and command_id. A SAS URI is a credential — it is not marked sensitive here, because doing so would redact the whole request body in every plan and make the script diff unreviewable; treat the value accordingly at the call site."
  default     = null

  validation {
    condition     = var.script_uri == null || can(regex("^https://", var.script_uri))
    error_message = "script_uri must be an https:// URL."
  }
}

variable "command_id" {
  type        = string
  description = "commandId of a script Azure ships, run instead of supplying your own. Windows: RunPowerShellScript, DisableNLA, DisableWindowsUpdate, EnableAdminAccount, EnableEMS, EnableRemotePS, EnableWindowsUpdate, IMDSCertCheck, IPConfig, RDPSettings, ResetRDPCert, SetRDPPort, WindowsActivationValidation, WindowsGhostedNicValidationScript, WindowsUpgradeAssessmentValidation. Linux has its own catalogue. Mutually exclusive with script and script_uri."
  default     = null

  # Deliberately not validated against a list. Azure extends the catalogue over
  # time and it differs per OS and per region — the authoritative list is
  # `Get-AzVMRunCommandDocument -Location <region>`. An allowlist here would
  # reject commands that work. An unknown ID fails at apply with "The entity was
  # not found in this Azure location", so only the shape is checked.
  validation {
    condition     = var.command_id == null || can(regex("^[A-Za-z0-9]+$", var.command_id))
    error_message = "command_id must be a non-empty alphanumeric commandId, e.g. EnableRemotePS."
  }
}

# -----------------------------------------------------------------------------
# Script inputs
# -----------------------------------------------------------------------------

variable "parameters" {
  type        = map(string)
  description = "Parameters passed to the script, keyed by parameter name. On Windows they arrive as named arguments (`-name value`); on Linux, named environment config. Values are strings only — the script converts. Positional Linux arguments (ARM's nameless parameters) cannot be expressed by a map and are out of scope; inline them in the script instead."
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for name in keys(var.parameters) : length(name) > 0])
    error_message = "parameters keys must be non-empty parameter names."
  }
}

variable "protected_parameters" {
  type        = map(string)
  description = "Secret parameters passed to the script, keyed by parameter name — passwords, keys, tokens. ARM accepts these write-only and never returns them, which is why this is the right channel for a secret rather than interpolating it into `script`, where the handler writes it to disk on the VM."
  default     = {}
  nullable    = false
  sensitive   = true

  validation {
    condition     = alltrue([for name in keys(var.protected_parameters) : length(name) > 0])
    error_message = "protected_parameters keys must be non-empty parameter names."
  }
}

# -----------------------------------------------------------------------------
# Execution
# -----------------------------------------------------------------------------

variable "async_execution" {
  type        = bool
  description = "Return as soon as the script starts instead of waiting for it to finish. Left false so the apply blocks until the script completes — which is what makes treat_failure_as_deployment_failure meaningful and lets an optional reboot land strictly after the script. Setting it true forfeits both."
  default     = false
  nullable    = false
}

variable "treat_failure_as_deployment_failure" {
  type        = bool
  description = "Fail the apply when the script fails. ARM defaults this to false, in which case provisioningState reflects only whether the platform managed to start the script and a script that throws applies clean; this module defaults it true. Requires API 2023-03-01 or later, which the pinned version satisfies."
  default     = true
  nullable    = false
}

variable "timeout_in_seconds" {
  type        = number
  description = "Script execution timeout, after which the platform stops it. Null leaves ARM's own default of 90 minutes in place. Managed run commands support genuinely long-running scripts, so there is no upper bound here — but raise `timeouts` to match, or Terraform gives up first."
  default     = null

  validation {
    condition     = var.timeout_in_seconds == null || var.timeout_in_seconds > 0
    error_message = "timeout_in_seconds must be a positive number of seconds."
  }
}

variable "run_as_user" {
  type        = string
  description = "Run the script as this local user instead of the default (System on Windows, root on Linux). The account must already exist on the VM and hold access to everything the script touches; on Windows the 'Secondary Logon' service must be running."
  default     = null
}

variable "run_as_password" {
  type        = string
  description = "Password for run_as_user. Write-only — ARM never returns it."
  default     = null
  sensitive   = true

  validation {
    condition     = var.run_as_password == null || var.run_as_user != null
    error_message = "run_as_password requires run_as_user to be set."
  }
}

# -----------------------------------------------------------------------------
# Output capture
# -----------------------------------------------------------------------------
# The instance view keeps only the last 4 KB of stdout and stderr. Anything
# larger has to be streamed to blobs, which is what these two are for.

variable "output_blob_uri" {
  type        = string
  description = "SAS URI of an append blob to stream stdout to, for output beyond the 4 KB the instance view retains. The blob must be of type AppendBlob and the SAS must grant read, add, create and write; it is created if absent and overwritten if present. Carries a credential — see the note on script_uri."
  default     = null

  validation {
    condition     = var.output_blob_uri == null || can(regex("^https://", var.output_blob_uri))
    error_message = "output_blob_uri must be an https:// URL."
  }
}

variable "error_blob_uri" {
  type        = string
  description = "SAS URI of an append blob to stream stderr to. Same blob type, permissions and caveats as output_blob_uri."
  default     = null

  validation {
    condition     = var.error_blob_uri == null || can(regex("^https://", var.error_blob_uri))
    error_message = "error_blob_uri must be an https:// URL."
  }
}

# -----------------------------------------------------------------------------
# Reboot
# -----------------------------------------------------------------------------

variable "reboot" {
  type        = bool
  description = "Restart the VM through ARM after the script completes, and block the apply until it is running again. Off by default because most scripts do not need it; turn it on for the ones whose effect only lands after a reboot — DisableNLA and a primary DNS suffix change among them."
  default     = false
  nullable    = false
}

variable "reboot_timeout" {
  type        = string
  description = "How long to wait for the restart to complete when reboot is true."
  default     = "15m"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.reboot_timeout))
    error_message = "reboot_timeout must be a Terraform duration such as 30s, 15m or 1h."
  }
}

# -----------------------------------------------------------------------------
# Retry — how a not-ready VM agent is absorbed
# -----------------------------------------------------------------------------

variable "retry" {
  type = object({
    error_message_regex  = list(string)
    interval_seconds     = optional(number)
    max_interval_seconds = optional(number)
    multiplier           = optional(number)
    randomization_factor = optional(number)
  })
  description = "Retry the write when the error message matches one of `error_message_regex`, applied to both the run command and the optional restart. Bounded by the Terraform context deadline, so `timeouts.create` decides how long retrying continues. Null disables it."
  default     = null

  validation {
    condition     = var.retry == null || length(try(var.retry.error_message_regex, [])) > 0
    error_message = "retry.error_message_regex must contain at least one pattern; leave retry null to disable retrying."
  }

  # regexall, not regex: regex() errors when the pattern does not match, so
  # can(regex(p, "")) rejects every pattern that simply is not present in the
  # empty string — which is all of them. regexall returns an empty list instead
  # and errors only on a genuinely invalid pattern, which is what is being
  # checked here.
  validation {
    condition     = var.retry == null || alltrue([for pattern in try(var.retry.error_message_regex, []) : can(regexall(pattern, ""))])
    error_message = "every retry.error_message_regex entry must be a valid regular expression."
  }
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "timeouts" {
  type = object({
    create = optional(string, "2h")
    update = optional(string, "2h")
    delete = optional(string, "30m")
  })
  description = "Terraform's deadlines for the run command resource — distinct from timeout_in_seconds, which bounds the script. These have to outlast it: the default 2h clears ARM's own 90-minute script default with room for the platform round-trip, and a script deliberately given longer needs these raised too."
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for duration in [var.timeouts.create, var.timeouts.update, var.timeouts.delete] :
      can(regex("^[0-9]+(s|m|h)$", duration))
    ])
    error_message = "timeouts values must be Terraform durations such as 30s, 15m or 2h."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the run command resource."
  default     = {}
  nullable    = false
}
