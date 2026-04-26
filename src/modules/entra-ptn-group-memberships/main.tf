# =============================================================================
# ENTRA ID GROUP MEMBERSHIPS (pattern module)
# =============================================================================
# Creates `azuread_group_member` resources for arbitrary (group, principal)
# pairs. Use this when the same principal needs to be a member of several
# groups, or when memberships are managed centrally outside the lifecycle of
# the groups themselves.
#
# `member` accepts either an Entra object ID (UUID) or a user principal name
# (UPN). UPN values are resolved via the `azuread_user` data source. Groups
# and service principals must be passed by object ID.
# =============================================================================

locals {
  uuid_pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

  upns = toset([
    for k, v in var.group_memberships : v.member
    if !can(regex(local.uuid_pattern, v.member))
  ])
}

data "azuread_user" "members" {
  for_each = local.upns

  user_principal_name = each.value
}

resource "azuread_group_member" "this" {
  for_each = var.group_memberships

  group_object_id = each.value.group_object_id
  member_object_id = (
    can(regex(local.uuid_pattern, each.value.member))
    ? each.value.member
    : data.azuread_user.members[each.value.member].object_id
  )
}
