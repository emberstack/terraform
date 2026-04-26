# =============================================================================
# ENTRA ID GROUP
# =============================================================================
# Owners can be passed as either Entra object IDs (UUIDs) or user principal
# names (UPNs). Auto-routed by format: UUID values are used directly, UPN
# values are resolved via the `azuread_user` data source (Graph lookup).
# Same convention applies to members (handled in the modules/member submodule).
# =============================================================================

locals {
  uuid_pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

  owners_by_object_id = { for k, v in var.owners : k => v if can(regex(local.uuid_pattern, v)) }
  owners_by_upn       = { for k, v in var.owners : k => v if !can(regex(local.uuid_pattern, v)) }
}

data "azuread_user" "owners" {
  for_each = toset(values(local.owners_by_upn))

  user_principal_name = each.value
}

resource "azuread_group" "this" {
  display_name            = var.display_name
  description             = var.description
  mail_enabled            = var.mail_enabled
  security_enabled        = var.security_enabled
  mail_nickname           = var.mail_nickname
  assignable_to_role      = var.assignable_to_role
  prevent_duplicate_names = var.prevent_duplicate_names
  visibility              = var.visibility
  types                   = var.types
  behaviors               = var.behaviors

  # Atomic AU placement: when non-empty, the group is created in the scope of
  # the first AU and added to the rest in a single Graph call. Pass null when
  # empty so we don't conflict with separate AU-membership management.
  administrative_unit_ids = length(var.administrative_unit_ids) > 0 ? var.administrative_unit_ids : null

  # Owners are managed inline (groups must always have ≥1 owner; the provider
  # auto-assigns the deploying principal as owner if `owners` is unset, which
  # is a footgun in CI/prod). UPN values are resolved via the data source above.
  owners = concat(
    values(local.owners_by_object_id),
    [for upn in values(local.owners_by_upn) : data.azuread_user.owners[upn].object_id]
  )

  dynamic "dynamic_membership" {
    for_each = var.dynamic_membership == null ? [] : [var.dynamic_membership]
    content {
      enabled = dynamic_membership.value.enabled
      rule    = dynamic_membership.value.rule
    }
  }

  # Members managed via the modules/member submodule below — do NOT also set
  # the resource's `members` attribute, the two methods conflict.
}

module "members" {
  source = "./modules/member"

  group_object_id = azuread_group.this.object_id
  members         = var.members
}
