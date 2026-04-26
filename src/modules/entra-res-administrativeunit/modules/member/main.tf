# =============================================================================
# ENTRA ID ADMINISTRATIVE UNIT MEMBER
# =============================================================================
# Membership is a separate submodule so it can be managed independently of the
# AU. Callers must NOT also set the parent's `members` attribute — the two
# methods conflict and produce persistent drift.
# =============================================================================

resource "azuread_administrative_unit_member" "this" {
  for_each = var.members

  administrative_unit_object_id = var.administrative_unit_object_id
  member_object_id              = each.value
}
