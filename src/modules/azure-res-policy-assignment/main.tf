# =============================================================================
# AZURE POLICY ASSIGNMENT (Microsoft.Authorization/policyAssignments)
# =============================================================================
# A single policy or initiative assignment at any scope. The scope is simply the
# resource's `parent_id`, so one resource covers all four:
#
#   /providers/Microsoft.Management/managementGroups/<mg>   -> management group
#   /subscriptions/<sub>                                    -> subscription
#   /subscriptions/<sub>/resourceGroups/<rg>                -> resource group
#   /subscriptions/<sub>/resourceGroups/<rg>/providers/...  -> resource
#
# The azurerm provider needed a distinct resource type per scope and a
# `terraform_data` precondition to police the routing; both are gone. Scope
# shape is now checked by a variable validation instead.
#
# When a managed identity is enabled, optional `identity_role_assignments` grant
# the system-assigned identity the roles a DeployIfNotExists / Modify policy
# needs — at the assignment scope by default, or anywhere you specify.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"

  has_user_assigned   = length(var.managed_identities.user_assigned_resource_ids) > 0
  has_system_assigned = var.managed_identities.system_assigned
  identity_type = (
    local.has_system_assigned && local.has_user_assigned ? "SystemAssigned, UserAssigned" :
    local.has_system_assigned ? "SystemAssigned" :
    local.has_user_assigned ? "UserAssigned" :
    null
  )

  # `identity` is written by the `dynamic "identity"` block below, but its
  # `principal_id` child is computed. The `try` is for the shape, not the value:
  # `identity[0]` is absent when refreshing or importing an assignment that has
  # no identity. An unknown `principal_id` propagates through `try` unchanged, as
  # it must — the role assignments below depend on it.
  system_identity_principal_id = local.has_system_assigned ? try(azapi_resource.this.identity[0].principal_id, null) : null

  # Kept only to preserve the `scope_kind` output; the resource itself no longer
  # branches on it, since the scope is just `parent_id`.
  #
  # Every matcher folds case, matching the `scope` validation: ARM segment names
  # are case-insensitive, so a `RESOURCEGROUPS`-cased scope is a valid resource
  # group and must not fall through to the "subscription" default.
  scope_kind = (
    can(regex("(?i)^/providers/Microsoft\\.Management/managementGroups/", var.scope)) ? "management_group" :
    can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/", var.scope)) ? "resource" :
    can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.scope)) ? "resource_group" :
    can(regex("(?i)^/subscriptions/[^/]+/providers/", var.scope)) ? "resource" :
    "subscription"
  )

  role_definition_name_to_resource_id = length(var.identity_role_assignments) > 0 ? {
    for definition in data.azapi_resource_list.role_definitions[0].output.results : definition.role_name => definition.id
  } : {}

  # An entry that is already a resource ID falls through the lookup untouched.
  role_definition_resource_ids = {
    for k, v in var.identity_role_assignments : k => lookup(
      local.role_definition_name_to_resource_id,
      v.role_definition_id_or_name,
      v.role_definition_id_or_name
    )
  }
}

# -----------------------------------------------------------------------------
# Policy assignment
# -----------------------------------------------------------------------------

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = var.scope
  type      = "Microsoft.Authorization/policyAssignments@2024-04-01"
  body = {
    properties = {
      definitionVersion = var.definition_version
      description       = var.description
      displayName       = var.display_name
      enforcementMode   = var.enforce ? "Default" : "DoNotEnforce"
      metadata          = length(var.metadata) > 0 ? var.metadata : null
      nonComplianceMessages = [for message in var.non_compliance_messages : {
        message                     = message.content
        policyDefinitionReferenceId = message.policy_definition_reference_id
      }]
      notScopes = sort(tolist(var.not_scopes))
      overrides = [for override in var.overrides : {
        kind = "policyEffect"
        selectors = [for selector in override.selectors : {
          in    = selector.in
          kind  = selector.kind
          notIn = selector.not_in
        }]
        value = override.value
      }]
      parameters         = length(var.parameters) > 0 ? var.parameters : null
      policyDefinitionId = var.policy_definition_id
      resourceSelectors = [for selector_name, selectors in var.resource_selectors : {
        name = selector_name
        selectors = [for selector in selectors : {
          in    = selector.in
          kind  = selector.kind
          notIn = selector.not_in
        }]
      }]
    }
  }
  # Azure fills `metadata` with its own audit fields and defaults
  # `definitionVersion`. Both are null here unless the caller sets them, and
  # without this that null would be treated as "clear it" on every write.
  ignore_null_property = true

  dynamic "identity" {
    for_each = local.identity_type == null ? [] : [local.identity_type]
    content {
      type         = identity.value
      identity_ids = var.managed_identities.user_assigned_resource_ids
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
# Only for the SYSTEM-assigned identity: it is created and destroyed with the
# assignment, so its grants belong here. A user-assigned identity outlives any
# single assignment, so the caller manages roles on the UAI itself. The
# principal ID is unknown until apply, which is why the resources below are also
# gated on `local.has_system_assigned`.

data "azapi_resource_list" "role_definitions" {
  count = length(var.identity_role_assignments) > 0 ? 1 : 0

  parent_id = local.subscription_resource_id
  type      = "Microsoft.Authorization/roleDefinitions@2022-04-01"
  response_export_values = {
    results = "value[].{id: id, role_name: properties.roleName}"
  }
}

resource "random_uuid" "identity_role_assignment_name" {
  for_each = local.has_system_assigned ? var.identity_role_assignments : {}
}

resource "azapi_resource" "identity_role_assignments" {
  for_each = local.has_system_assigned ? var.identity_role_assignments : {}

  name      = coalesce(each.value.name, random_uuid.identity_role_assignment_name[each.key].result)
  parent_id = coalesce(each.value.scope, var.scope)
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  body = {
    properties = {
      condition                          = each.value.condition
      conditionVersion                   = each.value.condition_version
      delegatedManagedIdentityResourceId = each.value.delegated_managed_identity_resource_id
      description                        = each.value.description
      principalId                        = local.system_identity_principal_id
      principalType                      = "ServicePrincipal"
      roleDefinitionId                   = local.role_definition_resource_ids[each.key]
    }
  }
  # Measured 2026-08-10 against roleAssignments@2022-04-01: ARM echoes an unset
  # `condition`, `conditionVersion`, `delegatedManagedIdentityResourceId` and
  # `description` back as explicit null, NOT as "". So a null sent here already
  # matches what ARM returns and this flag is belt-and-braces, not load-bearing.
  # Corroborated by azure-res-network-dnszone and -privatednszone, which write the
  # same body without the flag and plan clean against live assignments.
  # Kept because removing it is a behaviour change with nothing to gain.
  ignore_null_property = true
}
