# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "scope" {
  type        = string
  description = <<-EOT
    Default assignment scope for protected resources. Each entry in
    `protected_resources` can override this with its own `scope`.

    Typical values:
    - Management group: `/providers/Microsoft.Management/managementGroups/<mg>`
    - Subscription:     `/subscriptions/<sub>`
  EOT
  nullable    = false
}

variable "protected_resources" {
  type = map(object({
    resource_id = string
    # Null selects the field's default, and the default differs by field:
    # `scope`, `effect` and `non_compliance_message` fall back to the
    # module-level input of the same name; `display_name`, `description` and
    # `enforce` fall back to a built-in literal, with no module-level input to
    # inherit. A value here always wins.
    scope                  = optional(string, null)
    display_name           = optional(string, null)
    description            = optional(string, null)
    effect                 = optional(string, null)
    enforce                = optional(bool, null)
    non_compliance_message = optional(string, null)
  }))
  default     = {}
  description = <<-EOT
    Map of resources to protect, keyed by assignment name (1–24 chars for
    subscription/resource scope, 1–64 for management group).

    Required per entry:
    - `resource_id` — full ARM resource ID to protect.

    Optional per entry:
    - `scope`                  — assignment scope override (defaults to module-level `scope`).
    - `display_name`           — portal display name (defaults to "Aegis: <key>").
    - `description`            — long-form description.
    - `effect`                 — `DenyAction` or `Disabled` (defaults to module-level `effect`).
    - `enforce`                — whether enforced (defaults to true).
    - `non_compliance_message` — message override.
  EOT
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — behaviour
# -----------------------------------------------------------------------------

variable "effect" {
  type        = string
  default     = "DenyAction"
  description = "Default effect for all assignments. Per-resource `effect` overrides this."
  nullable    = false

  validation {
    condition     = contains(["DenyAction", "Disabled"], var.effect)
    error_message = "effect must be 'DenyAction' or 'Disabled'."
  }
}

variable "non_compliance_message" {
  type        = string
  default     = "This resource is explicitly protected by Aegis and cannot be deleted. Remove the policy assignment or create a policy exemption."
  description = "Default non-compliance message. Per-resource override available."
}

# -----------------------------------------------------------------------------
# Optional — definition placement
# -----------------------------------------------------------------------------

variable "policy_management_group_id" {
  type        = string
  default     = null
  description = <<-EOT
    Where the underlying policy definition lives. Set to a management group ID
    to publish it there (recommended); leave null for current subscription.
  EOT
}

variable "policy_metadata" {
  type        = any
  default     = {}
  description = "Extra metadata merged into the definition (over the built-in `category` and `version`)."
  nullable    = false
}
