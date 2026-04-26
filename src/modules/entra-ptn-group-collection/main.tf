# =============================================================================
# ENTRA ID GROUP COLLECTION (pattern module)
# =============================================================================
# Calls the singular `entra-res-group` module once per entry in
# `var.groups`. Each entry's input shape mirrors the resource module exactly.
#
# Validation, defaults, and the inline-owners + submodule-members semantics
# are inherited from the resource module — this wrapper only fans out.
# =============================================================================

module "group" {
  for_each = var.groups
  source   = "../entra-res-group"

  display_name            = each.value.display_name
  description             = each.value.description
  mail_enabled            = each.value.mail_enabled
  security_enabled        = each.value.security_enabled
  mail_nickname           = each.value.mail_nickname
  assignable_to_role      = each.value.assignable_to_role
  prevent_duplicate_names = each.value.prevent_duplicate_names
  visibility              = each.value.visibility
  types                   = each.value.types
  behaviors               = each.value.behaviors
  administrative_unit_ids = each.value.administrative_unit_ids
  dynamic_membership      = each.value.dynamic_membership
  owners                  = each.value.owners
  members                 = each.value.members
}
