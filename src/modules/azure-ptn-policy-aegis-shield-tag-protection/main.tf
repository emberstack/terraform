# =============================================================================
# AEGIS — TAG-PROTECTION SHIELD
# =============================================================================
# Turnkey deny-delete pattern.
#
# Drop-in guardrail: anything carrying the tag `aegis = deny-delete` is
# shielded from `delete` operations until the tag is removed.
#
# The tag (`aegis`), the trigger value (`deny-delete`), the case-insensitive
# match, the policy modes, and the cascade behaviour are all part of the
# pattern's contract — none of them are configurable. Only the effect
# (`DenyAction` or `Disabled`), the assignment scope, and the usual
# behaviour knobs (enforce / not_scopes / non-compliance message) are.
#
# Composition:
#   - 1x azure-res-policy-definition (mode `Indexed`) — protects resources,
#     with `cascadeBehaviors.resourceGroup = "deny"` so a tagged child also
#     blocks delete on its parent RG.
#   - 1x azure-res-policy-definition (mode `All`) — protects RGs that
#     themselves carry the tag (Indexed mode does not evaluate RGs).
#   - 1x azure-res-policy-set-definition — bundles the two policies into the
#     `aegis` initiative.
#   - 1x azure-res-policy-assignment — assigns the initiative at the
#     configured scope.
# =============================================================================

locals {
  # The Aegis tag is fixed by contract.
  tag_name      = "aegis"
  tag_value     = "deny-delete"
  tag_predicate = "[toLower(field('tags[''${local.tag_name}'']'))]"

  # Built-in `effect` parameter shape, reused on both definitions.
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

  resource_policy_name = "aegis-shield-tagged-resource-deny-delete"
  rg_policy_name       = "aegis-shield-tagged-resource-group-deny-delete"

  initiative_name         = coalesce(var.initiative_name, "aegis")
  assignment_default_name = coalesce(var.assignment_name, "aegis")
}

# -----------------------------------------------------------------------------
# Definition 1 — protects individual resources (Indexed mode + cascade)
# -----------------------------------------------------------------------------

module "definition_resource" {
  source = "../azure-res-policy-definition"

  name                = local.resource_policy_name
  display_name        = "Aegis: Deny deletion of shielded resources"
  description         = "Denies deletion of resources tagged with ${local.tag_name}=${local.tag_value}. To delete, remove the tag or create a policy exemption."
  mode                = "Indexed"
  management_group_id = var.policy_management_group_id
  metadata            = local.policy_metadata
  parameters          = local.effect_parameter

  policy_rule = {
    if = {
      value  = local.tag_predicate
      equals = local.tag_value
    }
    then = {
      effect = "[parameters('effect')]"
      details = {
        actionNames = ["delete"]
        cascadeBehaviors = {
          resourceGroup = "deny"
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Definition 2 — protects resource groups themselves (All mode)
# -----------------------------------------------------------------------------

module "definition_resource_group" {
  source = "../azure-res-policy-definition"

  name                = local.rg_policy_name
  display_name        = "Aegis: Deny deletion of shielded resource groups"
  description         = "Denies deletion of resource groups tagged with ${local.tag_name}=${local.tag_value}. To delete, remove the tag or create a policy exemption."
  mode                = "All"
  management_group_id = var.policy_management_group_id
  metadata            = local.policy_metadata
  parameters          = local.effect_parameter

  policy_rule = {
    if = {
      allOf = [
        { field = "type", equals = "Microsoft.Resources/subscriptions/resourceGroups" },
        { value = local.tag_predicate, equals = local.tag_value },
      ]
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
# Initiative — bundles both definitions
# -----------------------------------------------------------------------------

module "initiative" {
  source = "../azure-res-policy-set-definition"

  name                = local.initiative_name
  display_name        = coalesce(var.initiative_display_name, "Aegis Shield Protection")
  description         = coalesce(var.initiative_description, "Automated protection for tagged resources and resource groups.")
  management_group_id = var.policy_management_group_id
  metadata            = local.policy_metadata

  parameters = local.effect_parameter

  policy_definition_references = {
    (local.resource_policy_name) = {
      policy_definition_id = module.definition_resource.resource_id
      parameter_values = {
        effect = { value = "[parameters('effect')]" }
      }
    }
    (local.rg_policy_name) = {
      policy_definition_id = module.definition_resource_group.resource_id
      parameter_values = {
        effect = { value = "[parameters('effect')]" }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Assignment — applies the initiative at the configured scope
# -----------------------------------------------------------------------------

module "assignment" {
  source = "../azure-res-policy-assignment"

  name                 = local.assignment_default_name
  display_name         = coalesce(var.assignment_display_name, "Aegis Shield Protection")
  description          = coalesce(var.assignment_description, "Denies deletion of resources and resource groups tagged with ${local.tag_name}=${local.tag_value}.")
  scope                = var.scope
  policy_definition_id = module.initiative.resource_id
  enforce              = var.enforce
  not_scopes           = var.not_scopes

  parameters = {
    effect = { value = var.effect }
  }

  non_compliance_messages = length(var.non_compliance_message) > 0 ? [
    {
      content = var.non_compliance_message
    },
  ] : []
}
