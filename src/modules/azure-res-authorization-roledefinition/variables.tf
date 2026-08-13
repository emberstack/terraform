# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Human-readable role name shown in Azure RBAC. Must be unique within the role's `scope`."
  nullable    = false
}

variable "scope" {
  type        = string
  description = <<-EOT
    ARM resource ID where the role definition is anchored. Typically one of:

    - Management group: `/providers/Microsoft.Management/managementGroups/<mg>`
    - Subscription:     `/subscriptions/<sub>`

    The scope must be at or above any scope where the role will be assigned.
    Use the highest applicable management group for roles meant to be reused
    across multiple subscriptions.

    Segment names are matched case-insensitively, as ARM resource IDs are.
  EOT
  nullable    = false

  validation {
    # Same four matchers as azure-res-policy-assignment, folding case for the
    # same reason: ARM segment names are case-insensitive. Resource group and
    # resource are accepted even though they are not the documented anchors —
    # ARM permits a role definition there, and rejecting it here would make the
    # module stricter than the platform.
    condition = (
      can(regex("(?i)^/providers/Microsoft\\.Management/managementGroups/", var.scope)) ||
      can(regex("(?i)^/subscriptions/[^/]+$", var.scope)) ||
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.scope)) ||
      can(regex("(?i)^/subscriptions/[^/]+(/resourceGroups/[^/]+)?/providers/", var.scope))
    )
    error_message = "scope must be a management group, subscription, resource group, or resource ARM resource ID."
  }
}

# -----------------------------------------------------------------------------
# Optional — descriptive
# -----------------------------------------------------------------------------

variable "description" {
  type        = string
  default     = null
  description = "Long-form description shown in the portal. Recommended: explain *why* the role exists, not just what it grants."
}

variable "role_definition_id" {
  type        = string
  default     = null
  description = <<-EOT
    Optional fixed GUID for the role definition. When omitted, Azure auto-
    generates one on create. Set this to keep a stable ID across recreates
    (e.g. when an assignment elsewhere references the role by ID).
  EOT

  validation {
    condition     = var.role_definition_id == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.role_definition_id))
    error_message = "role_definition_id, when supplied, must be a lowercase GUID (e.g. 11111111-1111-1111-1111-111111111111)."
  }
}

# -----------------------------------------------------------------------------
# Optional — permissions
# -----------------------------------------------------------------------------

variable "actions" {
  type        = set(string)
  default     = []
  description = "Control-plane operations granted by the role (e.g. `Microsoft.Network/networkManagers/read`)."
  nullable    = false
}

variable "not_actions" {
  type        = set(string)
  default     = []
  description = "Control-plane operations explicitly removed from the inherited `actions`. Use sparingly — prefer narrowing `actions` instead."
  nullable    = false
}

variable "data_actions" {
  type        = set(string)
  default     = []
  description = "Data-plane operations granted by the role (e.g. `Microsoft.ContainerService/managedClusters/secrets/read`). Required for Kubernetes-RBAC-bridge scenarios. Note that a role definition containing `data_actions` cannot be assigned at management-group scope."
  nullable    = false
}

variable "not_data_actions" {
  type        = set(string)
  default     = []
  description = "Data-plane operations explicitly removed from `data_actions`."
  nullable    = false
}

variable "assignable_scopes" {
  type        = set(string)
  default     = []
  description = <<-EOT
    Set of scopes (ARM resource IDs) at which this role can be assigned. Each
    must be at or below `scope`. Defaults to `[scope]` when empty — i.e. the
    role can be assigned anywhere within the anchor scope.
  EOT
  nullable    = false

  validation {
    # Shape only. "At or below `scope`" is deliberately not checked: a
    # subscription below a management group does not share that group's ID
    # prefix, so the containment rule is not decidable from the strings alone.
    condition     = alltrue([for assignable_scope in var.assignable_scopes : startswith(assignable_scope, "/")])
    error_message = "assignable_scopes entries must be ARM resource IDs, each starting with `/`."
  }
}
