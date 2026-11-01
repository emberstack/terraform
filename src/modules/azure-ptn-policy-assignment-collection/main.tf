# =============================================================================
# AZURE POLICY ASSIGNMENTS (Microsoft.Authorization/policyAssignments)
# =============================================================================
# A set of policy or initiative assignments, each at its own scope, plus the
# role assignments their system-assigned identities need. Each entry mirrors
# `azure-res-policy-assignment`'s inputs field for field, except `parameters`
# and `metadata`, which are JSON strings here (see the variable).
#
# The resources are inlined rather than delegated to `azure-res-policy-assignment`,
# and they differ from it in one respect: unset optional fields are left out of
# the body instead of being sent as null under `ignore_null_property`. A change
# to that flag alone is a PUT, so adopting existing assignments by `terraform
# import` would cost a write on each.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The subscription the provider is configured against. Used to list the
  # roleDefinitions catalogue. Built-in roles are present in every subscription,
  # so this resolves any built-in name; a CUSTOM role defined in a different
  # subscription is not in this listing and must be passed as a resource ID.
  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"

  identity_types = {
    for k, a in var.assignments : k => (
      a.managed_identities.system_assigned && length(a.managed_identities.user_assigned_resource_ids) > 0 ? "SystemAssigned, UserAssigned" :
      a.managed_identities.system_assigned ? "SystemAssigned" :
      length(a.managed_identities.user_assigned_resource_ids) > 0 ? "UserAssigned" :
      null
    )
  }

  # `kind` plus whichever of `in` / `notIn` is set.
  selectors = {
    for k, a in var.assignments : k => {
      overrides = [for override in a.overrides : [
        for selector in override.selectors : merge(
          { kind = selector.kind },
          [for key, value in { in = selector.in, notIn = selector.not_in } : { (key) = value } if value != null]...
        )
      ]]
      resource_selectors = {
        for selector_name, selectors in a.resource_selectors : selector_name => [
          for selector in selectors : merge(
            { kind = selector.kind },
            [for key, value in { in = selector.in, notIn = selector.not_in } : { (key) = value } if value != null]...
          )
        ]
      }
    }
  }

  properties = {
    for k, a in var.assignments : k => merge(
      {
        enforcementMode    = a.enforce ? "Default" : "DoNotEnforce"
        policyDefinitionId = a.policy_definition_id
      },
      [for key, value in {
        definitionVersion = a.definition_version
        description       = a.description
        displayName       = a.display_name
        metadata          = a.metadata == null ? null : jsondecode(a.metadata)
        nonComplianceMessages = length(a.non_compliance_messages) == 0 ? null : [
          for message in a.non_compliance_messages : merge(
            { message = message.content },
            [for id in(message.policy_definition_reference_id == null ? [] : [message.policy_definition_reference_id]) : { policyDefinitionReferenceId = id }]...
          )
        ]
        notScopes = length(a.not_scopes) == 0 ? null : sort(a.not_scopes)
        overrides = length(a.overrides) == 0 ? null : [
          for i, override in a.overrides : {
            kind      = "policyEffect"
            selectors = local.selectors[k].overrides[i]
            value     = override.value
          }
        ]
        parameters = a.parameters == null ? null : jsondecode(a.parameters)
        resourceSelectors = length(a.resource_selectors) == 0 ? null : [
          for selector_name, selectors in local.selectors[k].resource_selectors : {
            name      = selector_name
            selectors = selectors
          }
        ]
      } : { (key) = value } if value != null]...
    )
  }

  # System-identity role assignments, flattened across all (assignment, role)
  # pairs. `assignment_key` and `ra_key` are carried so outputs can regroup them
  # under the assignment they belong to.
  identity_role_assignments = merge([
    for a_k, a in var.assignments : {
      for ra_k, ra in a.identity_role_assignments : "${a_k}-${ra_k}" => merge(ra, { assignment_key = a_k, ra_key = ra_k })
    } if a.managed_identities.system_assigned
  ]...)

  role_definition_names = [for ra in values(local.identity_role_assignments) : ra.role_definition_id_or_name]

  role_definition_name_to_resource_id = length(local.role_definition_names) > 0 ? {
    for definition in data.azapi_resource_list.role_definitions[0].output.results : definition.role_name => definition.id
  } : {}

  # Keyed by role, not by assignment key: a role definition is a property of the
  # ROLE, so two assignments naming the same role share one entry. An entry that is
  # already a resource ID falls through the lookup untouched and maps to itself.
  role_definition_resource_ids = {
    for name in toset(local.role_definition_names) :
    name => lookup(local.role_definition_name_to_resource_id, name, name)
  }
}

# -----------------------------------------------------------------------------
# Policy assignments
# -----------------------------------------------------------------------------

resource "azapi_resource" "this" {
  for_each = var.assignments

  location  = each.value.location
  name      = each.value.name
  parent_id = each.value.scope
  type      = "Microsoft.Authorization/policyAssignments@2024-04-01"
  body = {
    properties = local.properties[each.key]
  }

  dynamic "identity" {
    for_each = local.identity_types[each.key] == null ? [] : [local.identity_types[each.key]]
    content {
      type         = identity.value
      identity_ids = each.value.managed_identities.user_assigned_resource_ids
    }
  }
}

# -----------------------------------------------------------------------------
# Identity role assignments
# -----------------------------------------------------------------------------
# AzAPI has no equivalent of azurerm's `role_definition_name`, so role names are
# resolved against a subscription-scope listing, as the AVM interfaces module
# does.
#
# Assignment names are random UUIDs. ARM makes the name the resource identity,
# so deriving it from the principal would let an unknown-at-plan-time principal
# ID force a replacement. `name` is exposed for callers adopting an existing
# assignment.
#
# Only for SYSTEM-assigned identities: one is created and destroyed with its
# policy assignment, so its grants belong here. A user-assigned identity outlives
# any single assignment, so the caller manages roles on the UAI itself.

data "azapi_resource_list" "role_definitions" {
  count = length(local.role_definition_names) > 0 ? 1 : 0

  parent_id = local.provider_subscription_resource_id
  type      = "Microsoft.Authorization/roleDefinitions@2022-04-01"
  response_export_values = {
    results = "value[].{id: id, role_name: properties.roleName}"
  }
}

resource "random_uuid" "identity_role_assignment_name" {
  for_each = local.identity_role_assignments
}

resource "azapi_resource" "identity_role_assignments" {
  for_each = local.identity_role_assignments

  name      = coalesce(each.value.name, random_uuid.identity_role_assignment_name[each.key].result)
  parent_id = coalesce(each.value.scope, var.assignments[each.value.assignment_key].scope)
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  body = {
    properties = {
      condition                          = each.value.condition
      conditionVersion                   = each.value.condition_version
      delegatedManagedIdentityResourceId = each.value.delegated_managed_identity_resource_id
      description                        = each.value.description
      principalId                        = azapi_resource.this[each.value.assignment_key].identity[0].principal_id
      principalType                      = "ServicePrincipal"
      roleDefinitionId                   = local.role_definition_resource_ids[each.value.role_definition_id_or_name]
    }
  }

  lifecycle {
    precondition {
      # An unresolved name falls through the `lookup` default in
      # `role_definition_resource_ids` and reaches ARM as a bare string in
      # `roleDefinitionId`, which fails with an error naming neither the role nor
      # this assignment. Every resolved value is an ARM ID, so it starts with "/".
      condition     = startswith(local.role_definition_resource_ids[each.value.role_definition_id_or_name], "/")
      error_message = <<-EOT
        assignments["${each.value.assignment_key}"].identity_role_assignments["${each.value.ra_key}"]
        names the role "${each.value.role_definition_id_or_name}", which matched no role definition.

        Pass a role's display name exactly as Azure spells it, or a full
        role-definition resource ID. Names resolve against the roleDefinitions
        catalogue of the provider's subscription, so a CUSTOM role defined in a
        different subscription is not listed there and must be passed as an ID.
      EOT
    }
  }
}
