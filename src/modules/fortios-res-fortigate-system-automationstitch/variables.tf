# =============================================================================
# system/automation-stitch — wire an existing trigger to existing action(s).
# =============================================================================
# Stitch-only: the trigger and actions are referenced by name and must already
# exist (built-in or created elsewhere). Use this to compose FortiOS built-in
# triggers/actions without redefining them.
# =============================================================================

variable "name" {
  description = "Stitch name (mkey)."
  type        = string
}

variable "description" {
  description = "Free-text comment stored on the stitch. Empty leaves it blank."
  type        = string
  default     = ""
}

variable "status" {
  description = "enable | disable."
  type        = string
  default     = "enable"
}

variable "trigger" {
  description = "Name of an existing automation-trigger (built-in or managed)."
  type        = string
}

variable "actions" {
  description = "Ordered list of existing automation-action names to run when the trigger fires."
  type        = list(string)
}
