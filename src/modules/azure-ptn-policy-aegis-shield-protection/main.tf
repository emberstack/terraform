# =============================================================================
# AEGIS — RESOURCE SHIELD
# =============================================================================
# Explicit deny-delete protection by resource ID.
#
# Protects specific Azure resources from deletion via a DenyAction policy
# assigned per resource. Unlike the tag-based Aegis Shield, this targets
# resources explicitly by ARM ID — useful when tagging is not practical or
# when you need protection before the resource is created (tag-based policies
# only evaluate existing tags).
#
# Composition:
#   - 1x azure-res-policy-definition — the deny-delete-by-ID policy rule.
#   - Nx azure-res-policy-assignment — one per protected resource, each
#     binding the `protectedResourceId` parameter.
# =============================================================================

locals {
  definition_name = "aegis-shield-resource-deny-delete"

  effect_parameter = {
    effect = {
      type          = "String"
      allowedValues = ["DenyAction", "Disabled"]
      defaultValue  = "DenyAction"
      metadata = {
        displayName = "Effect"
        description = "Enable or disable the policy."
      }
    }
  }

  policy_metadata = merge(
    {
      category = "Governance"
      version  = "1.0.0"
    },
    var.policy_metadata,
  )
}

# -----------------------------------------------------------------------------
# Definition — deny delete by resource ID
# -----------------------------------------------------------------------------

module "definition" {
  source = "../azure-res-policy-definition"

  name                = local.definition_name
  display_name        = "Aegis Resource Shield"
  description         = "Denies deletion of a specific resource identified by its resource ID. To delete, remove the policy assignment or create a policy exemption."
  mode                = "All"
  management_group_id = var.policy_management_group_id
  metadata            = local.policy_metadata
  parameters = merge(local.effect_parameter, {
    protectedResourceId = {
      type = "String"
      metadata = {
        displayName = "Protected Resource ID"
        description = "The full ARM resource ID of the resource to protect from deletion."
      }
    }
  })

  policy_rule = {
    if = {
      field  = "id"
      equals = "[parameters('protectedResourceId')]"
    }
    then = {
      effect = "[parameters('effect')]"
      details = {
        actionNames = ["delete"]
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Assignments — one per protected resource
# -----------------------------------------------------------------------------

module "assignment" {
  source   = "../azure-res-policy-assignment"
  for_each = var.protected_resources

  name                 = each.key
  display_name         = coalesce(each.value.display_name, "Aegis: ${each.key}")
  description          = coalesce(each.value.description, "Denies deletion of a shielded resource. Remove the assignment or create a policy exemption to delete.")
  scope                = coalesce(each.value.scope, var.scope)
  policy_definition_id = module.definition.resource_id
  enforce              = coalesce(each.value.enforce, true)

  parameters = {
    protectedResourceId = { value = each.value.resource_id }
    effect              = { value = coalesce(each.value.effect, var.effect) }
  }

  non_compliance_messages = [{
    content = coalesce(each.value.non_compliance_message, var.non_compliance_message)
  }]
}
