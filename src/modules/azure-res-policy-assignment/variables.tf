# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = <<-EOT
    Assignment name. ARM's length limit depends on the scope: 1–64 characters at
    subscription, resource group and resource scope, but only 1–24 at management
    group scope. Both bounds are enforced against `scope`.
  EOT
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 64
    error_message = "name must be between 1 and 64 characters."
  }

  # Cross-variable check against `scope`. Note the direction — the tighter limit
  # is on MANAGEMENT GROUP scope, not on subscription scope, which is the opposite
  # of what it reads like and the opposite of what this module's own description
  # claimed until 2026-08-13. Source: the Microsoft resource-name-rules table
  # ("1-64 resource name, 1-24 resource name at management group scope"). The 64
  # is corroborated by a live subscription carrying 63-character assignment names;
  # the 24 is documentation only, since confirming it needs a failed create.
  validation {
    condition = (
      can(regex("(?i)^/providers/Microsoft\\.Management/managementGroups/", var.scope))
      ? length(var.name) <= 24
      : true
    )
    error_message = "name must be 24 characters or fewer at management-group scope, which is ARM's limit there. Subscription, resource group and resource scope allow up to 64."
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

    Segment names are matched case-insensitively, as ARM resource IDs are.
  EOT
  nullable    = false

  validation {
    # ARM segment names are case-insensitive and Azure accepts e.g.
    # `RESOURCEGROUPS`, so every matcher folds case. The `scope_kind` classifier
    # in main.tf folds the same way, so anything accepted here is classified on
    # its real shape rather than falling through to "subscription".
    condition = (
      can(regex("(?i)^/providers/Microsoft\\.Management/managementGroups/", var.scope)) ||
      can(regex("(?i)^/subscriptions/[^/]+$", var.scope)) ||
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.scope)) ||
      can(regex("(?i)^/subscriptions/[^/]+(/resourceGroups/[^/]+)?/providers/", var.scope))
    )
    error_message = "scope must be a management group, subscription, resource group, or resource ARM resource ID."
  }
}

variable "policy_definition_id" {
  type        = string
  description = "ARM resource ID of the policy definition or initiative being assigned."
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — display
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Optional — behaviour
# -----------------------------------------------------------------------------

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
    Parameter values bound at this assignment, as an HCL object. Sent to ARM as a
    native object; the module does not `jsonencode` it.

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

# -----------------------------------------------------------------------------
# Optional — identity
# -----------------------------------------------------------------------------

variable "location" {
  type        = string
  default     = null
  description = "Location for the assignment's managed identity. Required when `managed_identities.system_assigned = true`."

  validation {
    condition     = !var.managed_identities.system_assigned || var.location != null
    error_message = "location is required when managed_identities.system_assigned = true — ARM rejects a system-assigned identity without one."
  }
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

    Every assignment is sent with `principalType = "ServicePrincipal"`, since the
    principal is always the assignment's own identity, so ARM skips the directory
    lookup that fails on a freshly created principal.

    Has no effect when `managed_identities.system_assigned = false`. For UAIs,
    manage role assignments on the UAI directly (they outlive the policy
    assignment).
  EOT
  nullable    = false

  validation {
    condition = alltrue([
      for assignment in var.identity_role_assignments :
      assignment.name == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", assignment.name))
    ])
    error_message = "identity_role_assignments `name`, when supplied, must be a lowercase GUID (e.g. 11111111-1111-1111-1111-111111111111)."
  }
}
