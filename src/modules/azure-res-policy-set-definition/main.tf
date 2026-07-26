# =============================================================================
# AZURE POLICY SET DEFINITION (Microsoft.Authorization/policySetDefinitions)
# =============================================================================
# A custom policy initiative — a bundle of policy definitions exposed as a
# single assignable unit. Scope is implicit:
#   - management_group_id null -> azurerm_policy_set_definition (subscription)
#   - management_group_id set  -> azurerm_management_group_policy_set_definition
#
# Two resources rather than one because `management_group_id` on
# `azurerm_policy_set_definition` is deprecated and removed in azurerm v5. The
# provider offers no in-place successor, so the scope has to pick the type. The
# schemas are otherwise identical — same attributes, same nested blocks, same
# `min_items` — so nothing but the Terraform address changes.
#
# There is deliberately no `moved` block: azurerm does not implement MoveState
# for the pair, so one fails with "Move Resource State Not Supported". Switching
# scope therefore recreates the initiative and every assignment referencing it —
# see docs/modules/azure.md before upgrading a deny-effect initiative.
# =============================================================================

locals {
  at_management_group = var.management_group_id != null

  parameters = length(var.parameters) > 0 ? jsonencode(var.parameters) : null
  metadata   = length(var.metadata) > 0 ? jsonencode(var.metadata) : null
}

resource "azurerm_policy_set_definition" "subscription" {
  count = local.at_management_group ? 0 : 1

  name         = var.name
  policy_type  = "Custom"
  display_name = var.display_name
  description  = var.description

  parameters = local.parameters
  metadata   = local.metadata

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

resource "azurerm_management_group_policy_set_definition" "management_group" {
  count = local.at_management_group ? 1 : 0

  name                = var.name
  policy_type         = "Custom"
  display_name        = var.display_name
  description         = var.description
  management_group_id = var.management_group_id

  parameters = local.parameters
  metadata   = local.metadata

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
