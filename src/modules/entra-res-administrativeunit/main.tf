# =============================================================================
# ENTRA ID ADMINISTRATIVE UNIT
# =============================================================================

resource "azuread_administrative_unit" "this" {
  display_name              = var.display_name
  description               = var.description
  hidden_membership_enabled = var.hidden_membership_enabled
  prevent_duplicate_names   = var.prevent_duplicate_names
  # members managed via the modules/member submodule below — do NOT also set
  # the resource's `members` attribute, the two methods conflict.
}

module "members" {
  source = "./modules/member"

  administrative_unit_object_id = azuread_administrative_unit.this.object_id
  members                       = var.members
}

# =============================================================================
# AU-scoped directory role assignments (inline, AVM-style).
# `principal` accepts either UUID or UPN — auto-detected, UPN values resolved
# via `azuread_user` data source.
# =============================================================================

locals {
  uuid_pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

  role_assignment_upns = toset([
    for k, v in var.role_assignments : v.principal
    if !can(regex(local.uuid_pattern, v.principal))
  ])
}

data "azuread_user" "role_assignment_principals" {
  for_each = local.role_assignment_upns

  user_principal_name = each.value
}

resource "azuread_directory_role_assignment" "this" {
  for_each = var.role_assignments

  role_id = each.value.role_id
  principal_object_id = (
    can(regex(local.uuid_pattern, each.value.principal))
    ? each.value.principal
    : data.azuread_user.role_assignment_principals[each.value.principal].object_id
  )
  directory_scope_id = "/administrativeUnits/${azuread_administrative_unit.this.object_id}"
}
