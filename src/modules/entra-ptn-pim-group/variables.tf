variable "group_object_id" {
  description = "Object ID of the existing Entra group to bring under PIM for Groups. The group is not created by this module."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.group_object_id))
    error_message = "group_object_id must be a valid Entra object ID (UUID)."
  }

}

variable "policies" {
  description = <<-EOT
    Role management policies, keyed by PIM role — only `member` and `owner` are
    accepted, because Entra defines exactly two policies per group.

    ## Partial management

    `azuread_group_role_management_policy` adopts a policy Entra already created,
    so this module manages a *subset* of policy state, not the whole thing.
    Three levels, and the difference matters:

      | You write                       | Effect                                 |
      |---------------------------------|----------------------------------------|
      | block omitted                   | not managed — existing value survives  |
      | block present, attribute omitted| not managed — existing value survives  |
      | attribute set                   | managed — overwrites existing value    |

    Consequently **no attribute below carries a default**. A default would be
    indistinguishable from a caller's choice and would silently overwrite the
    adopted policy. The one exception is `notifications.*.notification_level`
    and `default_recipients`, which the provider requires whenever a recipient
    block is present.

    Two blocks cannot be partially managed, because the provider requires an
    expiry decision whenever the block exists: `active_assignments` and
    `eligible_assignments` both take a mandatory `expiration`:

      | `expiration`                         | Effect                           |
      |--------------------------------------|----------------------------------|
      | `permitted`                          | permanent assignments allowed    |
      | `required`                           | must expire; adopted maximum kept|
      | `P15D`/`P30D`/`P90D`/`P180D`/`P365D` | must expire, within that maximum |

    It is mandatory rather than defaulted on purpose: deriving it from another
    attribute would mean touching the block to HARDEN something also wrote a
    silent loosening. Omit the block entirely to leave the expiry decision alone.

    ## Collapsed conflict pairs

    Several provider attributes are deliberately **not** exposed because they
    form mutually exclusive pairs a caller could otherwise set into an invalid
    combination. Each pair is collapsed into one knob:

      | Not exposed                                         | Derived from            |
      |-----------------------------------------------------|-------------------------|
      | `require_multifactor_authentication` +               | `authentication.method` |
      | `required_conditional_access_authentication_context` |                         |
      | `expiration_required` + `expire_after`               | `expiration` (above)    |
      | `require_approval` + `approval_stage`                | `approvers` (below)     |

    `approvers` is tri-state: omitted = approval not managed; `{}` = approval
    explicitly disabled; non-empty = approval required with those approvers.
    That is what makes `require_approval = true` with an empty approval stage
    unrepresentable while still allowing "leave approval alone".
  EOT

  type = map(object({
    activation = optional(object({
      # ISO8601, from the provider's enum: PT30M, PT1H..PT23H30M in 30-minute
      # steps, or P1D. Note P1D, NOT PT1D — the provider rejects the latter.
      maximum_duration      = optional(string)
      require_justification = optional(bool)
      require_ticket_info   = optional(bool)

      # Omit    -> neither authentication gate is managed.
      # Provide -> `method` selects exactly one of them.
      authentication = optional(object({
        method                 = string
        authentication_context = optional(string)
      }))

      approvers = optional(map(object({
        object_id = string
        type      = string
      })))
    }))

    # `require_ticket_info` is deliberately absent here: the provider only emits
    # the underlying rule when MFA or justification also changed, and never reads
    # it back, so the knob would be silently write-only and permanently
    # undetectable as drift. It IS honoured under `activation`.
    active_assignments = optional(object({
      expiration                         = string
      require_justification              = optional(bool)
      require_multifactor_authentication = optional(bool)
    }))

    eligible_assignments = optional(object({
      expiration = string
    }))

    notifications = optional(object({
      eligible_assignments = optional(object({
        admin = optional(object({
          notification_level    = optional(string, "All")
          default_recipients    = optional(bool, true)
          additional_recipients = optional(list(string))
        }))
        approver = optional(object({
          notification_level    = optional(string, "All")
          default_recipients    = optional(bool, true)
          additional_recipients = optional(list(string))
        }))
        assignee = optional(object({
          notification_level    = optional(string, "All")
          default_recipients    = optional(bool, true)
          additional_recipients = optional(list(string))
        }))
      }))
      active_assignments = optional(object({
        admin = optional(object({
          notification_level    = optional(string, "All")
          default_recipients    = optional(bool, true)
          additional_recipients = optional(list(string))
        }))
        approver = optional(object({
          notification_level    = optional(string, "All")
          default_recipients    = optional(bool, true)
          additional_recipients = optional(list(string))
        }))
        assignee = optional(object({
          notification_level    = optional(string, "All")
          default_recipients    = optional(bool, true)
          additional_recipients = optional(list(string))
        }))
      }))
      eligible_activations = optional(object({
        admin = optional(object({
          notification_level    = optional(string, "All")
          default_recipients    = optional(bool, true)
          additional_recipients = optional(list(string))
        }))
        approver = optional(object({
          notification_level    = optional(string, "All")
          default_recipients    = optional(bool, true)
          additional_recipients = optional(list(string))
        }))
        assignee = optional(object({
          notification_level    = optional(string, "All")
          default_recipients    = optional(bool, true)
          additional_recipients = optional(list(string))
        }))
      }))
    }))
  }))

  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.policies) : contains(["member", "owner"], k)])
    error_message = "policies keys must be either \"member\" or \"owner\"."
  }


  # Enum needles are guarded against an explicitly-null value: `contains()`
  # rejects a null needle with a raw function error, which aborts variable
  # evaluation instead of producing the message below. A required object
  # attribute can still be set to null by the caller, so this is reachable.
  validation {
    condition = alltrue([
      for p in values(var.policies) :
      contains(["mfa", "conditional_access", "none"], p.activation.authentication.method == null ? "" : p.activation.authentication.method)
      if p.activation != null && p.activation.authentication != null
    ])
    error_message = "activation.authentication.method must be one of \"mfa\", \"conditional_access\", or \"none\"."
  }

  # Guards the one pair the provider marks ConflictsWith: an auth context is
  # meaningful only for the conditional_access method.
  validation {
    condition = alltrue([
      for p in values(var.policies) :
      (p.activation.authentication.method == "conditional_access") == (p.activation.authentication.authentication_context != null)
      if p.activation != null && p.activation.authentication != null
    ])
    error_message = "activation.authentication.authentication_context must be set when method is \"conditional_access\", and omitted otherwise."
  }

  # The provider validates this with a StringInSlice, reproduced verbatim rather
  # than approximated with a regex. A regex previously admitted "PT1D" (which the
  # provider rejects) while rejecting "P1D" (which it requires) — wrong in both
  # directions at once.
  validation {
    condition = alltrue([
      for p in values(var.policies) :
      contains([
        "PT30M", "PT1H", "PT1H30M", "PT2H", "PT2H30M", "PT3H", "PT3H30M", "PT4H",
        "PT4H30M", "PT5H", "PT5H30M", "PT6H", "PT6H30M", "PT7H", "PT7H30M", "PT8H",
        "PT8H30M", "PT9H", "PT9H30M", "PT10H", "PT10H30M", "PT11H", "PT11H30M",
        "PT12H", "PT12H30M", "PT13H", "PT13H30M", "PT14H", "PT14H30M", "PT15H",
        "PT15H30M", "PT16H", "PT16H30M", "PT17H", "PT17H30M", "PT18H", "PT18H30M",
        "PT19H", "PT19H30M", "PT20H", "PT20H30M", "PT21H", "PT21H30M", "PT22H",
        "PT22H30M", "PT23H", "PT23H30M", "P1D",
      ], p.activation.maximum_duration)
      if p.activation != null && p.activation.maximum_duration != null
    ])
    error_message = "activation.maximum_duration must be PT30M, one of PT1H..PT23H30M in 30-minute steps, or P1D (note P1D, not PT1D)."
  }

  validation {
    condition = alltrue(flatten([
      for p in values(var.policies) : [
        for a in values(p.activation.approvers) : contains(["singleUser", "groupMembers"], a.type == null ? "" : a.type)
      ] if p.activation != null && p.activation.approvers != null
    ]))
    error_message = "activation.approvers[*].type must be either \"singleUser\" or \"groupMembers\"."
  }

  validation {
    condition = alltrue(flatten([
      for p in values(var.policies) : [
        for a in values(p.activation.approvers) :
        can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", a.object_id))
      ] if p.activation != null && p.activation.approvers != null
    ]))
    error_message = "activation.approvers[*].object_id must be a valid Entra object ID (UUID)."
  }

  validation {
    condition = alltrue([
      for p in values(var.policies) :
      contains(["permitted", "required", "P15D", "P30D", "P90D", "P180D", "P365D"], p.active_assignments.expiration == null ? "" : p.active_assignments.expiration)
      if p.active_assignments != null
    ])
    error_message = "active_assignments.expiration must be \"permitted\", \"required\", or one of P15D, P30D, P90D, P180D, P365D."
  }

  validation {
    condition = alltrue([
      for p in values(var.policies) :
      contains(["permitted", "required", "P15D", "P30D", "P90D", "P180D", "P365D"], p.eligible_assignments.expiration == null ? "" : p.eligible_assignments.expiration)
      if p.eligible_assignments != null
    ])
    error_message = "eligible_assignments.expiration must be \"permitted\", \"required\", or one of P15D, P30D, P90D, P180D, P365D."
  }

  # The provider rejects an event block with no recipient.
  validation {
    condition = alltrue(flatten([
      for p in values(var.policies) : [
        for event in [
          p.notifications.eligible_assignments,
          p.notifications.active_assignments,
          p.notifications.eligible_activations,
        ] : (event.admin != null || event.approver != null || event.assignee != null) if event != null
      ] if p.notifications != null
    ]))
    error_message = "Each notifications event must set at least one of admin, approver, or assignee."
  }

  validation {
    condition = alltrue(flatten([
      for p in values(var.policies) : [
        for event in [
          p.notifications.eligible_assignments,
          p.notifications.active_assignments,
          p.notifications.eligible_activations,
          ] : [
          for r in [event.admin, event.approver, event.assignee] :
          contains(["All", "Critical"], r.notification_level) if r != null
        ] if event != null
      ] if p.notifications != null
    ]))
    error_message = "notifications notification_level must be either \"All\" or \"Critical\"."
  }
}

variable "eligibility" {
  description = <<-EOT
    Eligibility schedules, keyed by a stable caller-chosen identifier.

    `principal` is **either** an Entra object ID (UUID) **or** a user principal
    name, auto-detected by format. UPNs are resolved through the `azuread_user`
    data source at plan time, so principal *values* must be known at plan time —
    pass an object ID when one is produced by another resource. App-only callers
    need `User.Read.All` for the UPN lookup; object IDs need no directory read.

    A principal may be a user **or a group**, and a group has no UPN, so groups
    are always given as object IDs. A group as an eligible principal is how a
    roster group is bound to a role-assignable target: Entra forbids a group as
    an *active* member of a role-assignable group but permits it as an *eligible*
    one, and activation resolves per user rather than for the whole group.

    Omit `duration` for permanent eligibility. `expiration_date` is deliberately
    not exposed — it is a third way to express what `duration` already says, and
    exposing both reintroduces a conflict surface. Express absolute end dates as
    a duration from `start_date`.
  EOT

  type = map(object({
    principal       = string
    assignment_type = string
    justification   = optional(string)
    ticket_number   = optional(string)
    ticket_system   = optional(string)
    start_date      = optional(string)
    duration        = optional(string)
  }))

  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for s in values(var.eligibility) : contains(["member", "owner"], s.assignment_type == null ? "" : s.assignment_type)])
    error_message = "eligibility[*].assignment_type must be either \"member\" or \"owner\"."
  }

  validation {
    condition = alltrue([
      for s in values(var.eligibility) :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", s.principal)) ||
      can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", s.principal))
    ])
    error_message = "eligibility[*].principal must be either a valid Entra object ID (UUID) or a user principal name (UPN, e.g. user@example.com). A group principal has no UPN — pass its object ID."
  }

  # Every component of an ISO8601 duration is optional, so a naive pattern also
  # admits the degenerate forms "P", "PT", "P30DT" and "P0D". The provider only
  # applies StringIsNotEmpty and forwards the value verbatim to Graph, so the
  # trailing-designator and at-least-one-non-zero-digit checks are the backstop.
  validation {
    condition = alltrue([
      for s in values(var.eligibility) :
      can(regex("^P(?:\\d+[YMWD])*(?:T(?:\\d+[HMS])+)?$", s.duration)) && can(regex("[1-9]", s.duration))
      if s.duration != null
    ])
    error_message = "eligibility[*].duration must be a non-zero ISO8601 duration (e.g. P30D, PT3H). Omit it for permanent eligibility."
  }

  validation {
    condition = alltrue([
      for s in values(var.eligibility) : can(formatdate("YYYY-MM-DD", s.start_date)) if s.start_date != null
    ])
    error_message = "eligibility[*].start_date must be an RFC3339 timestamp (e.g. 2026-01-01T00:00:00Z)."
  }

  # Cross-variable: a permanent schedule needs a policy that permits permanence.
  #
  # SCOPE — this catches the unbounded case only. A schedule whose `duration`
  # merely EXCEEDS the policy's maximum is not caught here: comparing them means
  # parsing arbitrary ISO8601 against the enum, and the mismatch is a loud,
  # deterministic Graph rejection at apply rather than a silent wrong state. It
  # also requires the policy for that role to be managed in the same call;
  # against an unmanaged or portal-configured policy it cannot fire.
  validation {
    condition = alltrue([
      for s in values(var.eligibility) : !(
        s.duration == null &&
        try(var.policies[s.assignment_type].eligible_assignments.expiration, "permitted") != "permitted"
      )
    ])
    error_message = "A permanent eligibility (duration omitted) conflicts with eligible_assignments.expiration on the same role's policy. Set that policy's expiration to \"permitted\", or give the eligibility a duration."
  }
}

variable "assignments" {
  description = <<-EOT
    Active assignment schedules, keyed by a stable caller-chosen identifier.

    `principal` accepts an object ID or a UPN on the same terms as
    `eligibility` — see that variable for the plan-time and permission caveats.

    Omit `duration` for a permanent active assignment. See `eligibility` for why
    `expiration_date` is not exposed.
  EOT

  type = map(object({
    principal       = string
    assignment_type = string
    justification   = optional(string)
    ticket_number   = optional(string)
    ticket_system   = optional(string)
    start_date      = optional(string)
    duration        = optional(string)
  }))

  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for s in values(var.assignments) : contains(["member", "owner"], s.assignment_type == null ? "" : s.assignment_type)])
    error_message = "assignments[*].assignment_type must be either \"member\" or \"owner\"."
  }

  validation {
    condition = alltrue([
      for s in values(var.assignments) :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", s.principal)) ||
      can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", s.principal))
    ])
    error_message = "assignments[*].principal must be either a valid Entra object ID (UUID) or a user principal name (UPN, e.g. user@example.com). A group principal has no UPN — pass its object ID."
  }

  validation {
    condition = alltrue([
      for s in values(var.assignments) :
      can(regex("^P(?:\\d+[YMWD])*(?:T(?:\\d+[HMS])+)?$", s.duration)) && can(regex("[1-9]", s.duration))
      if s.duration != null
    ])
    error_message = "assignments[*].duration must be a non-zero ISO8601 duration (e.g. P30D, PT3H). Omit it for a permanent assignment."
  }

  validation {
    condition = alltrue([
      for s in values(var.assignments) : can(formatdate("YYYY-MM-DD", s.start_date)) if s.start_date != null
    ])
    error_message = "assignments[*].start_date must be an RFC3339 timestamp (e.g. 2026-01-01T00:00:00Z)."
  }

  # Cross-variable — see the equivalent check on `eligibility` for scope.
  validation {
    condition = alltrue([
      for s in values(var.assignments) : !(
        s.duration == null &&
        try(var.policies[s.assignment_type].active_assignments.expiration, "permitted") != "permitted"
      )
    ])
    error_message = "A permanent assignment (duration omitted) conflicts with active_assignments.expiration on the same role's policy. Set that policy's expiration to \"permitted\", or give the assignment a duration."
  }

  # "The module must do something" — spans all three collections, so its
  # placement is constrained twice over: a condition must reference the variable
  # it is declared on, and Terraform rejects a *cycle* between validations. Both
  # `eligibility` and `assignments` already reference `policies`, so hanging this
  # on `policies` closes a loop and fails with "Cycle: var.assignments
  # (validation), var.eligibility (validation), var.policies (validation)".
  # Declared here, the edges stay a DAG. Keep that in mind before adding a
  # cross-variable check that points the other way.
  validation {
    condition = (
      length(var.assignments) > 0 ||
      length(var.policies) > 0 ||
      length(var.eligibility) > 0
    )
    error_message = "At least one of policies, eligibility, or assignments must be set."
  }
}
