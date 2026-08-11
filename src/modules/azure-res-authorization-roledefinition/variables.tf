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
  EOT
  nullable    = false
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
}
