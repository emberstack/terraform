# =============================================================================
# AZURE CUSTOM ROLE DEFINITION COLLECTION
# =============================================================================
# Manages a map of custom RBAC role definitions through a single module call.
# Each entry composes one `azure-res-authorization-roledefinition`.
#
# Custom roles are typically anchored at one shared scope (a management group
# or a subscription) and reused across many assignments — the collection
# accepts a single module-level `scope` and applies it to every entry by
# default. Per-entry `scope` and `assignable_scopes` overrides are supported
# for the rare case where a single deployment manages roles at mixed scopes.
# =============================================================================

module "role_definition" {
  source   = "../azure-res-authorization-roledefinition"
  for_each = var.role_definitions

  name        = each.value.name
  scope       = coalesce(each.value.scope, var.scope)
  description = each.value.description

  actions          = each.value.actions
  not_actions      = each.value.not_actions
  data_actions     = each.value.data_actions
  not_data_actions = each.value.not_data_actions

  assignable_scopes  = each.value.assignable_scopes
  role_definition_id = each.value.role_definition_id
}
