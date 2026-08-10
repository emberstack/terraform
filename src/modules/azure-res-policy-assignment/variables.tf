# =============================================================================
# Required
# =============================================================================

variable "name" {
  type        = string
  description = "Assignment name. 1–24 chars at subscription/resource scope; 1–64 chars at management-group scope."
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 64
    error_message = "name must be between 1 and 64 characters."
  }
}

variable "definition_version" {
  type        = string
  default     = null
  description = <<-EOT
    Version of the policy definition to bind, e.g. `1.*.*`.

    Left null, Azure picks its own default and this module does not manage the field —
    an existing pinned version is preserved rather than reset.
  EOT
}

variable "scope" {
  type        = string
  description = <<-EOT
    ARM resource ID where the policy is assigned. Detected formats:

    - Management group: `/providers/Microsoft.Management/managementGroups/<mg>`
    - Subscription:     `/subscriptions/<sub>`
    - Resource group:   `/subscriptions/<sub>/resourceGroups/<rg>`
    - Resource:         `/subscriptions/<sub>/resourceGroups/<rg>/providers/<...>`
  EOT
  nullable    = false
  validation {
    condition = (
      startswith(var.scope, "/providers/Microsoft.Management/managementGroups/") ||
      can(regex("^/subscriptions/[^/]+$", var.scope)) ||
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.scope)) ||
      can(regex("^/subscriptions/[^/]+(/resourceGroups/[^/]+)?/providers/", var.scope))
    )
    error_message = "scope must be a management group, subscription, resource group, or resource ARM resource ID."
  }
}

variable "policy_definition_id" {
  type        = string
  description = "ARM resource ID of the policy definition or initiative being assigned."
  nullable    = false
}

# =============================================================================
# Optional — display
# =============================================================================

variable "display_name" {
  type        = string
  default     = null
  description = "Human-readable display name. Defaults to `name` in the portal."
}

variable "description" {
  type        = string
  default     = null
  description = "Long-form description shown in the portal."
}

# =============================================================================
# Optional — behavior
# =============================================================================

variable "enforce" {
  type        = bool
  default     = true
  description = "Whether the policy is enforced. Set to false for an audit-only / dry-run mode."
  nullable    = false
}

variable "not_scopes" {
  type        = list(string)
  default     = []
  description = "List of ARM resource IDs to exclude from the assignment scope."
  nullable    = false
}

variable "parameters" {
  type        = any
  default     = {}
  description = <<-EOT
    Parameter values bound at this assignment, as an HCL object. The module
    `jsonencode`s it.

    Each entry shape:
    ```
    effect = { value = "Deny" }
    ```
  EOT
  nullable    = false
}

variable "metadata" {
  type        = any
  default     = {}
  description = "Assignment metadata as an HCL object."
  nullable    = false
}

variable "non_compliance_messages" {
  type = list(object({
    content                        = string
    policy_definition_reference_id = optional(string, null)
  }))
  default     = []
  description = <<-EOT
    Messages shown when the policy reports non-compliance.

    Set `policy_definition_reference_id` to target a specific policy inside an
    initiative; leave null for an assignment-wide message.
  EOT
  nullable    = false
}

variable "overrides" {
  type = list(object({
    value = string
    selectors = optional(list(object({
      kind   = string
      in     = optional(list(string), null)
      not_in = optional(list(string), null)
    })), [])
  }))
  default     = []
  description = "Effect overrides — replace the policy effect at evaluation time. See provider docs for `overrides` block."
  nullable    = false
}

variable "resource_selectors" {
  type = map(list(object({
    kind   = string
    in     = optional(list(string), null)
    not_in = optional(list(string), null)
  })))
  default     = {}
  description = <<-EOT
    Resource selectors keyed by selector name. Each value is the list of
    `selectors` blocks (kinds: `resourceLocation`, `resourceType`,
    `resourceWithoutLocation`).
  EOT
  nullable    = false
}

# =============================================================================
# Optional — identity
# =============================================================================

variable "location" {
  type        = string
  default     = null
  description = "Location for the assignment's managed identity. Required when `managed_identities.system_assigned = true`."
}

variable "managed_identities" {
  type = object({
    system_assigned            = optional(bool, false)
    user_assigned_resource_ids = optional(set(string), [])
  })
  default     = {}
  description = <<-EOT
    Managed identity attached to the assignment, used by DeployIfNotExists and
    Modify policies during remediation.

    - `system_assigned`: enable a system-assigned identity at assignment scope.
    - `user_assigned_resource_ids`: ARM IDs of UAIs to attach.

    When `system_assigned = true` the module also requires `location`.
  EOT
  nullable    = false
}

variable "identity_role_assignments" {
  type = map(object({
    name                                   = optional(string, null)
    role_definition_id_or_name             = string
    scope                                  = optional(string, null)
    description                            = optional(string, null)
    skip_service_principal_aad_check       = optional(bool, false)
    condition                              = optional(string, null)
    condition_version                      = optional(string, null)
    delegated_managed_identity_resource_id = optional(string, null)
  }))
  default     = {}
  description = <<-EOT
    Role assignments granted to the **system-assigned identity**, keyed by
    stable name. Defaults to the assignment scope when `scope` is null.

    Use this to grant the remediation identity the rights it needs (e.g.
    `Contributor` on a workload subscription for a DeployIfNotExists policy).

    `role_definition_id_or_name` accepts either a role display name or an ARM
    role-definition resource ID — auto-routed by the leading `/`.

    Has no effect when `managed_identities.system_assigned = false`. For UAIs,
    manage role assignments on the UAI directly (they outlive the policy
    assignment).
  EOT
  nullable    = false
}

