# =============================================================================
# AZURE POLICY DEFINITION (Microsoft.Authorization/policyDefinitions)
# =============================================================================
# A single custom Azure Policy definition. Scope is implicit:
#   - management_group_id set -> scoped to that management group
#   - management_group_id null -> scoped to the current subscription
#
# Inputs accept HCL maps/lists where the underlying resource expects JSON, and
# the module handles `jsonencode` so callers don't have to manage stringly-typed
# fields.
# =============================================================================

resource "azurerm_policy_definition" "this" {
  name                = var.name
  policy_type         = "Custom"
  mode                = var.mode
  display_name        = var.display_name
  description         = var.description
  management_group_id = var.management_group_id

  policy_rule = jsonencode(var.policy_rule)
  parameters  = length(var.parameters) > 0 ? jsonencode(var.parameters) : null
  metadata    = length(var.metadata) > 0 ? jsonencode(var.metadata) : null
}
