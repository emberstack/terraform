# =============================================================================
# AZURE POLICY SET DEFINITION (Microsoft.Authorization/policySetDefinitions)
# =============================================================================
# A single custom initiative. Scope is implicit:
#   - management_group_id set  -> scoped to that management group
#   - management_group_id null -> scoped to the current subscription
#
# One resource covers both scopes, because the scope is just `parent_id`. The
# azurerm provider needed two distinct resource types here
# (`azurerm_policy_set_definition` and `azurerm_management_group_policy_set_definition`)
# and could not `moved` between them — that whole problem disappears.
#
# `parameters`, `metadata` and each reference's `parameter_values` are sent as
# native objects rather than JSON-encoded strings.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  scope_resource_id = coalesce(
    var.management_group_id,
    "/subscriptions/${data.azapi_client_config.current.subscription_id}",
  )
}

resource "azapi_resource" "this" {
  name      = var.name
  parent_id = local.scope_resource_id
  type      = "Microsoft.Authorization/policySetDefinitions@2023-04-01"
  body = {
    properties = {
      description = var.description
      displayName = var.display_name
      metadata    = length(var.metadata) > 0 ? var.metadata : null
      parameters  = length(var.parameters) > 0 ? var.parameters : null
      policyDefinitionGroups = [
        for group_name, group in var.policy_definition_groups : {
          additionalMetadataId = group.additional_metadata_resource_id
          category             = group.category
          description          = group.description
          displayName          = group.display_name
          name                 = group_name
        }
      ]
      policyDefinitions = [
        for reference_id, reference in var.policy_definition_references : {
          groupNames                  = sort(tolist(coalesce(reference.policy_group_names, [])))
          parameters                  = length(reference.parameter_values) > 0 ? reference.parameter_values : null
          policyDefinitionId          = reference.policy_definition_id
          policyDefinitionReferenceId = reference_id
        }
      ]
      policyType = "Custom"
    }
  }
  # Same as `azure-res-policy-definition`: ARM injects
  # `createdBy`/`createdOn`/`updatedBy`/`updatedOn` into `metadata` (measured
  # 2026-08-10, on the `aegis` initiative), so a caller that omits `metadata`
  # would compare null against a populated object forever.
  ignore_null_property = true
}
