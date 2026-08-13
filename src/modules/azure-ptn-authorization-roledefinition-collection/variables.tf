# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "role_definitions" {
  type = map(object({
    name               = string
    description        = optional(string, null)
    actions            = optional(set(string), [])
    not_actions        = optional(set(string), [])
    data_actions       = optional(set(string), [])
    not_data_actions   = optional(set(string), [])
    assignable_scopes  = optional(set(string), [])
    scope              = optional(string, null)
    role_definition_id = optional(string, null)
  }))
  description = <<-EOT
    Map of custom role definitions, keyed by stable identifier (e.g.
    `network_manager_reader`). Each entry maps onto one
    `azure-res-authorization-roledefinition` invocation.

    Required per entry:
    - `name` — human-readable role name shown in Azure RBAC.

    Optional per entry:
    - `description`        — long-form description.
    - `actions`            — control-plane operations granted.
    - `not_actions`        — operations subtracted from `actions`.
    - `data_actions`       — data-plane operations granted.
    - `not_data_actions`   — operations subtracted from `data_actions`.
    - `assignable_scopes`  — scopes at which the role can be assigned. Defaults to the entry's `scope`.
    - `scope`              — per-entry anchor scope override. Defaults to the module-level `scope`.
    - `role_definition_id` — fixed role-definition GUID (auto-generated when omitted).
  EOT
  nullable    = false

  validation {
    condition     = alltrue([for v in values(var.role_definitions) : v.scope != null || var.scope != null])
    error_message = "Every role definition must have a scope. Provide either the module-level `scope` or a per-entry `scope`."
  }
}

# -----------------------------------------------------------------------------
# Optional — scope
# -----------------------------------------------------------------------------

variable "scope" {
  type        = string
  default     = null
  description = <<-EOT
    Default anchor scope applied to every role definition that does not
    override it. Required unless every entry in `role_definitions` sets its
    own `scope`.

    Typical values:
    - Management group: `/providers/Microsoft.Management/managementGroups/<mg>`
    - Subscription:     `/subscriptions/<sub>`
  EOT
}
