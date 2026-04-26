# =============================================================================
# AZURE POLICY SET DEFINITION (Microsoft.Authorization/policySetDefinitions)
# =============================================================================
# A custom policy initiative — a bundle of policy definitions exposed as a
# single assignable unit. Scope is implicit:
#   - management_group_id set -> management group
#   - management_group_id null -> current subscription
# =============================================================================

resource "azurerm_policy_set_definition" "this" {
  name                = var.name
  policy_type         = "Custom"
  display_name        = var.display_name
  description         = var.description
  management_group_id = var.management_group_id

  parameters = length(var.parameters) > 0 ? jsonencode(var.parameters) : null
  metadata   = length(var.metadata) > 0 ? jsonencode(var.metadata) : null

  dynamic "policy_definition_reference" {
    for_each = var.policy_definition_references
    content {
      policy_definition_id = policy_definition_reference.value.policy_definition_id
      reference_id         = policy_definition_reference.key
      parameter_values     = length(policy_definition_reference.value.parameter_values) > 0 ? jsonencode(policy_definition_reference.value.parameter_values) : null
      policy_group_names   = policy_definition_reference.value.policy_group_names
    }
  }

  dynamic "policy_definition_group" {
    for_each = var.policy_definition_groups
    content {
      name                            = policy_definition_group.key
      display_name                    = policy_definition_group.value.display_name
      category                        = policy_definition_group.value.category
      description                     = policy_definition_group.value.description
      additional_metadata_resource_id = policy_definition_group.value.additional_metadata_resource_id
    }
  }
}
