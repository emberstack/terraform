# =============================================================================
# PIM FOR GROUPS
# =============================================================================
# Brings an existing Entra group under PIM for Groups and manages its role
# management policies and eligible/active schedules.
#
# ADOPTION, NOT CREATION
# Entra materialises a role management policy for every group on demand, and
# `azuread_group_role_management_policy` takes over the existing one. Terraform
# still *reports* it as "will be created" and counts it in "N to add" — there is
# no prior state entry — but no new directory object appears. The practical
# consequence is that a first apply overwrites whatever the portal had for every
# attribute this module sets.
#
# PARTIAL MANAGEMENT
# Because of that adoption, unset attributes must stay unset rather than carry a
# default: the provider marks them Computed, so a null passes through as
# "inherit the adopted value". This is why nothing in variables.tf defaults —
# a default is indistinguishable from a caller's choice and would silently
# rewrite the adopted policy. See the `policies` description for the three
# levels.
#
# COLLAPSED CONFLICT PAIRS
# The provider marks several attribute pairs mutually exclusive. The variable
# exposes one knob per pair and this file derives both sides, so a caller cannot
# express an invalid combination. Two caveats worth knowing:
#
#   * The unused side of a pair is passed as **null**, not false/"". Those pairs
#     are ConflictsWith in the provider schema and only null reads as absent —
#     a literal `false` can still trip it.
#   * Because null means "inherit" on a Computed attribute, this prevents you
#     from *writing* a conflicting pair; it cannot guarantee the adopted policy
#     ends up with only one side set. If an existing policy already carries a
#     conditional-access context and you select method = "mfa", the context is
#     not necessarily cleared. Conflict-free config, best-effort API state.
#
# REQUIRED GRAPH PERMISSIONS
# `RoleManagementPolicy.ReadWrite.AzureADGroup` plus, for the schedules,
# `PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup` and
# `PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup`. Neither the Azure CLI
# nor Azure PowerShell first-party client is preauthorized for these, so
# `use_cli` / `use_powershell` authentication fails with 403
# PermissionScopeNotGranted no matter which directory role the signed-in user
# holds. This module requires app-only authentication (client secret,
# certificate or OIDC) against an application granted those permissions.
# =============================================================================

resource "azuread_group_role_management_policy" "this" {
  for_each = var.policies

  group_id = var.group_object_id
  role_id  = each.key

  dynamic "activation_rules" {
    for_each = each.value.activation == null ? [] : [each.value.activation]
    content {
      maximum_duration      = activation_rules.value.maximum_duration
      require_justification = activation_rules.value.require_justification
      require_ticket_info   = activation_rules.value.require_ticket_info

      require_multifactor_authentication = (
        activation_rules.value.authentication == null ? null :
        activation_rules.value.authentication.method == "mfa" ? true :
        activation_rules.value.authentication.method == "none" ? false : null
      )
      required_conditional_access_authentication_context = (
        activation_rules.value.authentication == null ? null :
        activation_rules.value.authentication.method == "conditional_access"
        ? activation_rules.value.authentication.authentication_context
        : null
      )

      # Tri-state: null approvers leaves approval unmanaged, an empty map
      # disables it, a populated map requires it. Approval is never an
      # independent switch, which is what makes require_approval = true with an
      # empty approval stage unrepresentable.
      require_approval = (
        activation_rules.value.approvers == null
        ? null
        : length(activation_rules.value.approvers) > 0
      )

      dynamic "approval_stage" {
        for_each = length(activation_rules.value.approvers == null ? {} : activation_rules.value.approvers) > 0 ? [1] : []
        content {
          dynamic "primary_approver" {
            for_each = activation_rules.value.approvers
            content {
              object_id = primary_approver.value.object_id
              type      = primary_approver.value.type
            }
          }
        }
      }
    }
  }

  # The provider requires an expiry decision whenever this block exists, so
  # `expiration` is mandatory rather than derived from an unrelated attribute.
  # Deriving it from `expire_after != null` would mean that touching this block
  # to HARDEN something (say require_justification) silently wrote
  # expiration_required = false over the adopted policy — a loosening the caller
  # never asked for. "required" keeps the adopted maximum duration because
  # expire_after is Computed; verified accepted by the provider.
  dynamic "active_assignment_rules" {
    for_each = each.value.active_assignments == null ? [] : [each.value.active_assignments]
    content {
      expiration_required = active_assignment_rules.value.expiration != "permitted"
      expire_after = (
        contains(["permitted", "required"], active_assignment_rules.value.expiration)
        ? null
        : active_assignment_rules.value.expiration
      )

      require_justification              = active_assignment_rules.value.require_justification
      require_multifactor_authentication = active_assignment_rules.value.require_multifactor_authentication
    }
  }

  dynamic "eligible_assignment_rules" {
    for_each = each.value.eligible_assignments == null ? [] : [each.value.eligible_assignments]
    content {
      expiration_required = eligible_assignment_rules.value.expiration != "permitted"
      expire_after = (
        contains(["permitted", "required"], eligible_assignment_rules.value.expiration)
        ? null
        : eligible_assignment_rules.value.expiration
      )
    }
  }

  # Block labels cannot be computed, so the three events and their three
  # recipient kinds are written out rather than looped.
  dynamic "notification_rules" {
    for_each = each.value.notifications == null ? [] : [each.value.notifications]
    content {
      dynamic "eligible_assignments" {
        for_each = notification_rules.value.eligible_assignments == null ? [] : [notification_rules.value.eligible_assignments]
        content {
          dynamic "admin_notifications" {
            for_each = eligible_assignments.value.admin == null ? [] : [eligible_assignments.value.admin]
            content {
              notification_level    = admin_notifications.value.notification_level
              default_recipients    = admin_notifications.value.default_recipients
              additional_recipients = admin_notifications.value.additional_recipients
            }
          }
          dynamic "approver_notifications" {
            for_each = eligible_assignments.value.approver == null ? [] : [eligible_assignments.value.approver]
            content {
              notification_level    = approver_notifications.value.notification_level
              default_recipients    = approver_notifications.value.default_recipients
              additional_recipients = approver_notifications.value.additional_recipients
            }
          }
          dynamic "assignee_notifications" {
            for_each = eligible_assignments.value.assignee == null ? [] : [eligible_assignments.value.assignee]
            content {
              notification_level    = assignee_notifications.value.notification_level
              default_recipients    = assignee_notifications.value.default_recipients
              additional_recipients = assignee_notifications.value.additional_recipients
            }
          }
        }
      }

      dynamic "active_assignments" {
        for_each = notification_rules.value.active_assignments == null ? [] : [notification_rules.value.active_assignments]
        content {
          dynamic "admin_notifications" {
            for_each = active_assignments.value.admin == null ? [] : [active_assignments.value.admin]
            content {
              notification_level    = admin_notifications.value.notification_level
              default_recipients    = admin_notifications.value.default_recipients
              additional_recipients = admin_notifications.value.additional_recipients
            }
          }
          dynamic "approver_notifications" {
            for_each = active_assignments.value.approver == null ? [] : [active_assignments.value.approver]
            content {
              notification_level    = approver_notifications.value.notification_level
              default_recipients    = approver_notifications.value.default_recipients
              additional_recipients = approver_notifications.value.additional_recipients
            }
          }
          dynamic "assignee_notifications" {
            for_each = active_assignments.value.assignee == null ? [] : [active_assignments.value.assignee]
            content {
              notification_level    = assignee_notifications.value.notification_level
              default_recipients    = assignee_notifications.value.default_recipients
              additional_recipients = assignee_notifications.value.additional_recipients
            }
          }
        }
      }

      dynamic "eligible_activations" {
        for_each = notification_rules.value.eligible_activations == null ? [] : [notification_rules.value.eligible_activations]
        content {
          dynamic "admin_notifications" {
            for_each = eligible_activations.value.admin == null ? [] : [eligible_activations.value.admin]
            content {
              notification_level    = admin_notifications.value.notification_level
              default_recipients    = admin_notifications.value.default_recipients
              additional_recipients = admin_notifications.value.additional_recipients
            }
          }
          dynamic "approver_notifications" {
            for_each = eligible_activations.value.approver == null ? [] : [eligible_activations.value.approver]
            content {
              notification_level    = approver_notifications.value.notification_level
              default_recipients    = approver_notifications.value.default_recipients
              additional_recipients = approver_notifications.value.additional_recipients
            }
          }
          dynamic "assignee_notifications" {
            for_each = eligible_activations.value.assignee == null ? [] : [eligible_activations.value.assignee]
            content {
              notification_level    = assignee_notifications.value.notification_level
              default_recipients    = assignee_notifications.value.default_recipients
              additional_recipients = assignee_notifications.value.additional_recipients
            }
          }
        }
      }
    }
  }
}

# =============================================================================
# SCHEDULES
# =============================================================================
# Ordered after the policies: a permanent schedule is rejected unless the policy
# permits permanence. Terraform cannot infer that edge — the schedule references
# the group object ID, not the policy resource — so it is declared explicitly.
#
# KNOWN LIMITATION — expiration_date outranks the `duration` knob.
# The provider builds the schedule request by preferring expiration_date, then
# duration, then permanent_assignment. `expiration_date` is Optional+Computed and
# this module never sets it, so once the API has populated it in state, that
# value wins over a later change here and the schedule will not converge.
# Exposing expiration_date would reintroduce the very conflict pair the design
# removes, so instead: if a schedule needs to move to permanent (or to a
# different duration) after its expiration_date has been populated, replace the
# resource — `terraform apply -replace=...` on that schedule address.
#
# PRINCIPALS — OBJECT ID OR UPN
# `principal` is auto-routed by format: UUID values are used directly, UPN
# values are resolved through the `azuread_user` data source. Both schedule maps
# share one lookup, keyed by the UPN itself.
#
# Resource `for_each` is keyed on the input map, NOT on a regex-filtered copy.
# Filtering by value makes the whole map unknown at plan time as soon as any
# principal comes from another resource, and Terraform then rejects the for_each
# outright. Only the data source below is value-derived, so principal *values*
# must be known at plan time — pass an object ID when one comes from another
# resource.
#
# A group is a legal principal here and has no UPN, so groups are always passed
# as object IDs. App-only callers additionally need `User.Read.All` for the UPN
# lookup; object IDs need no directory read at all.
# =============================================================================

locals {
  uuid_pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

  schedule_principal_upns = toset([
    for s in concat(values(var.eligibility), values(var.assignments)) :
    s.principal if !can(regex(local.uuid_pattern, s.principal))
  ])
}

data "azuread_user" "this" {
  for_each = local.schedule_principal_upns

  user_principal_name = each.value
}

resource "azuread_privileged_access_group_eligibility_schedule" "this" {
  for_each = var.eligibility

  group_id = var.group_object_id
  principal_id = (
    can(regex(local.uuid_pattern, each.value.principal))
    ? each.value.principal
    : data.azuread_user.this[each.value.principal].object_id
  )
  assignment_type = each.value.assignment_type

  justification = each.value.justification
  ticket_number = each.value.ticket_number
  ticket_system = each.value.ticket_system
  start_date    = each.value.start_date

  duration             = each.value.duration
  permanent_assignment = each.value.duration == null ? true : null

  depends_on = [azuread_group_role_management_policy.this]
}

resource "azuread_privileged_access_group_assignment_schedule" "this" {
  for_each = var.assignments

  group_id = var.group_object_id
  principal_id = (
    can(regex(local.uuid_pattern, each.value.principal))
    ? each.value.principal
    : data.azuread_user.this[each.value.principal].object_id
  )
  assignment_type = each.value.assignment_type

  justification = each.value.justification
  ticket_number = each.value.ticket_number
  ticket_system = each.value.ticket_system
  start_date    = each.value.start_date

  duration             = each.value.duration
  permanent_assignment = each.value.duration == null ? true : null

  depends_on = [azuread_group_role_management_policy.this]
}
