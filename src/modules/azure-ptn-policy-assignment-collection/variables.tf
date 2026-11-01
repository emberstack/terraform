variable "assignments" {
  type = map(object({
    name                 = string
    scope                = string
    policy_definition_id = string
    definition_version   = optional(string, null)
    display_name         = optional(string, null)
    description          = optional(string, null)
    enforce              = optional(bool, true)
    not_scopes           = optional(list(string), [])
    parameters           = optional(string, null)
    metadata             = optional(string, null)
    non_compliance_messages = optional(list(object({
      content                        = string
      policy_definition_reference_id = optional(string, null)
    })), [])
    overrides = optional(list(object({
      value = string
      selectors = optional(list(object({
        kind   = string
        in     = optional(list(string), null)
        not_in = optional(list(string), null)
      })), [])
    })), [])
    resource_selectors = optional(map(list(object({
      kind   = string
      in     = optional(list(string), null)
      not_in = optional(list(string), null)
    }))), {})
    location = optional(string, null)
    managed_identities = optional(object({
      system_assigned            = optional(bool, false)
      user_assigned_resource_ids = optional(set(string), [])
    }), {})
    identity_role_assignments = optional(map(object({
      name                                   = optional(string, null)
      role_definition_id_or_name             = string
      scope                                  = optional(string, null)
      description                            = optional(string, null)
      condition                              = optional(string, null)
      condition_version                      = optional(string, null)
      delegated_managed_identity_resource_id = optional(string, null)
    })), {})
  }))
  default     = {}
  description = <<-EOT
    Policy or initiative assignments, keyed by a stable snake_case handle. Each
    entry carries the inputs of `azure-res-policy-assignment`, with the same
    meaning and defaults; see that module for each field.

    `parameters` and `metadata` are JSON strings — `jsonencode({ ... })` in the
    caller — where `azure-res-policy-assignment` takes HCL objects. A map of
    objects needs one type for every entry, so an `any`-typed field fails
    as soon as one assignment passes a list-valued parameter (allowed locations)
    and another a string-valued one (an effect).

    `parameters` shape, before encoding:
    ```
    { effect = { value = "Audit" } }
    ```

    Keys must be snake_case: an identity role assignment's state address is the
    assignment key and its own key joined with `-`.
  EOT
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.assignments) : can(regex("^[a-z0-9]+(_[a-z0-9]+)*$", k))])
    error_message = "Every assignments key must match ^[a-z0-9]+(_[a-z0-9]+)*$ (lower-case snake_case), so the `<assignment>-<role>` state address of an identity role assignment cannot collide."
  }

  validation {
    condition = alltrue(flatten([
      for a in values(var.assignments) : [for k in keys(a.identity_role_assignments) : can(regex("^[a-z0-9]+(_[a-z0-9]+)*$", k))]
    ]))
    error_message = "Every identity_role_assignments key must match ^[a-z0-9]+(_[a-z0-9]+)*$ (lower-case snake_case), for the same reason as the assignment keys."
  }

  validation {
    condition = alltrue([
      for a in values(var.assignments) : (
        can(regex("(?i)^/providers/Microsoft\\.Management/managementGroups/", a.scope)) ||
        can(regex("(?i)^/subscriptions/[^/]+$", a.scope)) ||
        can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+$", a.scope)) ||
        can(regex("(?i)^/subscriptions/[^/]+(/resourceGroups/[^/]+)?/providers/", a.scope))
      )
    ])
    error_message = "Every assignments[*].scope must be a management group, subscription, resource group, or resource ARM resource ID."
  }

  # The limit is tighter at management-group scope, as in azure-res-policy-assignment.
  validation {
    condition = alltrue([
      for a in values(var.assignments) :
      length(a.name) >= 1 && length(a.name) <= (can(regex("(?i)^/providers/Microsoft\\.Management/managementGroups/", a.scope)) ? 24 : 64)
    ])
    error_message = "assignments[*].name must be 1–64 characters, or 1–24 at management-group scope."
  }

  validation {
    condition = alltrue([
      for a in values(var.assignments) :
      (a.parameters == null || can(keys(jsondecode(a.parameters)))) && (a.metadata == null || can(keys(jsondecode(a.metadata))))
    ])
    error_message = "assignments[*].parameters and metadata must be JSON-encoded objects."
  }

  validation {
    condition     = alltrue([for a in values(var.assignments) : !a.managed_identities.system_assigned || a.location != null])
    error_message = "assignments[*].location is required when managed_identities.system_assigned = true — ARM rejects a system-assigned identity without one."
  }

  validation {
    condition = alltrue(flatten([
      for a in values(var.assignments) : [
        for ra in values(a.identity_role_assignments) :
        ra.name == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", ra.name))
      ]
    ]))
    error_message = "identity_role_assignments `name`, when supplied, must be a lowercase GUID (e.g. 11111111-1111-1111-1111-111111111111)."
  }
}
