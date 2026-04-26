# =============================================================================
# AZURE CUSTOM ROLE DEFINITION (Microsoft.Authorization/roleDefinitions)
# =============================================================================
# A single custom RBAC role definition. Anchored to one scope (typically a
# management group at or above the assignments) and assignable at one or more
# `assignable_scopes`. When `assignable_scopes` is omitted it defaults to the
# definition's own scope.
# =============================================================================

resource "azurerm_role_definition" "this" {
  name               = var.name
  scope              = var.scope
  description        = var.description
  assignable_scopes  = length(var.assignable_scopes) > 0 ? var.assignable_scopes : [var.scope]
  role_definition_id = var.role_definition_id

  permissions {
    actions          = var.actions
    not_actions      = var.not_actions
    data_actions     = var.data_actions
    not_data_actions = var.not_data_actions
  }
}
