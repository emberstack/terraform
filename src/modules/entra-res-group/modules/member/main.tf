# =============================================================================
# ENTRA ID GROUP MEMBER
# =============================================================================
# Members can be passed as either Entra object IDs (UUIDs) or user principal
# names (UPNs). Auto-routed by format: UUID values are used directly, UPN
# values are resolved via the `azuread_user` data source (Graph lookup).
#
# `for_each` is keyed on `var.members` itself, NOT on a regex-filtered copy of
# it. Filtering by value makes the whole map unknown at plan time as soon as any
# member comes from another resource, and Terraform then rejects the for_each
# outright. Keying on the raw input keeps the addresses plannable and the
# UUID-vs-UPN decision happens per-entry in the body instead.
#
# The data source below is still value-derived and cannot be keyed statically,
# so member *values* must be known at plan time. Pass object IDs directly when
# they come from another resource.
# =============================================================================

locals {
  uuid_pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

  members_by_upn = { for k, v in var.members : k => v if !can(regex(local.uuid_pattern, v)) }
}

data "azuread_user" "this" {
  for_each = toset(values(local.members_by_upn))

  user_principal_name = each.value
}

resource "azuread_group_member" "this" {
  for_each = var.members

  group_object_id = var.group_object_id
  member_object_id = (
    can(regex(local.uuid_pattern, each.value))
    ? each.value
    : data.azuread_user.this[each.value].object_id
  )
}
