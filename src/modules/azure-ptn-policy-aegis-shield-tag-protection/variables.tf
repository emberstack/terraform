# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "scope" {
  type        = string
  description = <<-EOT
    ARM resource ID where the assignment lands. Any of:

    - Management group: `/providers/Microsoft.Management/managementGroups/<mg>`
    - Subscription:     `/subscriptions/<sub>`
    - Resource group:   `/subscriptions/<sub>/resourceGroups/<rg>`
    - Resource:         `/subscriptions/<sub>/resourceGroups/<rg>/providers/<...>`
  EOT
  nullable    = false
}

# -----------------------------------------------------------------------------
# The protection tag is fixed by contract
# -----------------------------------------------------------------------------
# The pattern matches resources where `tags['aegis']` (case-insensitive) equals
# `deny-delete`. None of these are configurable — every Aegis-protected
# resource across every consumer uses exactly the same tag and value, so
# operators can grep, audit, and reason about protection consistently.

# -----------------------------------------------------------------------------
# Optional — assignment behaviour
# -----------------------------------------------------------------------------

variable "effect" {
  type        = string
  default     = "DenyAction"
  description = <<-EOT
    Effect bound to the policy's `effect` parameter at assignment time.

    - `DenyAction` — blocks delete operations (default).
    - `Disabled`   — turns the shield off without unassigning.

    `Audit` is intentionally not offered: the underlying `denyAction` effect
    has no audit semantics — Azure Policy reports non-compliance only when an
    actual delete is attempted and blocked, so an audit-only mode would emit
    no useful signal.
  EOT
  nullable    = false

  validation {
    condition     = contains(["DenyAction", "Disabled"], var.effect)
    error_message = "effect must be 'DenyAction' or 'Disabled'."
  }
}

variable "enforce" {
  type        = bool
  default     = true
  description = "Whether the assignment is enforced. Set to false to fully dry-run."
  nullable    = false
}

variable "not_scopes" {
  type        = list(string)
  default     = []
  description = "List of ARM resource IDs to exclude from the shield."
  nullable    = false
}

variable "non_compliance_message" {
  type        = string
  default     = "This resource carries the aegis protection tag and cannot be deleted. Remove the tag first, or create a policy exemption."
  description = "Message shown to users who hit the deny."
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — definition placement and labels
# -----------------------------------------------------------------------------

variable "policy_management_group_id" {
  type        = string
  default     = null
  description = <<-EOT
    Where the underlying policy definitions and the initiative live.

    - Set to a management group ID to publish them there (recommended so
      multiple subscriptions can reuse the same definitions via separate
      assignments).
    - Leave null to publish at the current subscription.

    Independent of `scope` — the assignment can land anywhere, regardless of
    where the definitions are published, as long as the assignment scope can
    see them (subscription assignments can use definitions in their parent
    management groups).
  EOT
}

variable "policy_metadata" {
  type        = any
  default     = {}
  description = "Extra metadata merged into both definitions and the initiative (over the built-in `category = \"Governance\"` and `version = \"1.0.0\"`)."
  nullable    = false
}

variable "initiative_name" {
  type        = string
  default     = null
  description = "Custom name for the initiative (policy set definition). Defaults to `aegis`."
}

variable "initiative_display_name" {
  type        = string
  default     = null
  description = "Custom display name for the initiative. Defaults to `Aegis Shield Protection`."
}

variable "initiative_description" {
  type        = string
  default     = null
  description = "Custom description for the initiative."
}

variable "assignment_name" {
  type        = string
  default     = null
  description = "Custom name for the assignment. Defaults to `aegis`."
}

variable "assignment_display_name" {
  type        = string
  default     = null
  description = "Custom display name for the assignment. Defaults to `Aegis Shield Protection`."
}

variable "assignment_description" {
  type        = string
  default     = null
  description = "Custom description for the assignment."
}
