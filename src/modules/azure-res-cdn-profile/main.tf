# =============================================================================
# AZURE FRONT DOOR PROFILE (Microsoft.Cdn/profiles)
# =============================================================================
# A Front Door Standard or Premium profile. `Microsoft.Cdn/profiles` also
# carries the classic Azure CDN SKUs, whose children are a different family
# (`endpoints` rather than `afdEndpoints`), so `sku` is validated to the two
# `*_AzureFrontDoor` values only.
#
# A profile is a global resource: `location` is always `global`, whatever region
# the resource group is in.
#
# Origin groups and endpoints usually belong to whoever owns the origin, so they
# are submodules (`modules/origin-group`, `modules/afd-endpoint`) that take this
# profile's `resource_id`, rather than inputs here.
#
# `frontDoorId` is the value Front Door sends to every origin in the
# `X-Azure-FDID` header, the documented way for a public origin to accept only
# its own profile's traffic. It is exported as `front_door_id`.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The input stays a plain resource group name (AVM's shape); the subscription
  # comes from the configured provider, so an aliased or multi-subscription
  # caller still lands in the right place.
  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  resource_group_resource_id        = "${local.provider_subscription_resource_id}/resourceGroups/${var.resource_group_name}"

  has_user_assigned   = length(var.managed_identities.user_assigned_resource_ids) > 0
  has_system_assigned = var.managed_identities.system_assigned
  identity_type = (
    local.has_system_assigned && local.has_user_assigned ? "SystemAssigned, UserAssigned" :
    local.has_system_assigned ? "SystemAssigned" :
    local.has_user_assigned ? "UserAssigned" :
    null
  )

  # Optional keys are added with `merge(base, [for _ in <0 or 1 items> : {...}]...)`:
  # a conditional between `{}` and an object with attributes is a type error.
  profile_properties = merge(
    {
      originResponseTimeoutSeconds = var.origin_response_timeout_seconds
    },
    [
      for scrubbing in var.log_scrubbing == null ? [] : [var.log_scrubbing] : {
        logScrubbing = {
          scrubbingRules = [
            for rule in scrubbing.rules : merge(
              {
                matchVariable         = rule.match_variable
                selectorMatchOperator = "EqualsAny"
                state                 = rule.enabled ? "Enabled" : "Disabled"
              },
              [for selector in rule.selector == null ? [] : [rule.selector] : { selector = selector }]...
            )
          ]
          state = scrubbing.enabled ? "Enabled" : "Disabled"
        }
      }
    ]...
  )

  # Every role this module assigns, as the caller spelled it — a display name or an
  # ARM resource ID. Deduplication happens in `role_definition_resource_ids`.
  role_definition_names = [for v in values(var.role_assignments) : v.role_definition_id_or_name]

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

  # ARM materialises every category with a retention policy of its own, deprecated
  # and always off. Sent in full so the arrays compare equal; anything less leaves
  # the diagnostic setting diff on every plan.
  diagnostic_retention_policy = { days = 0, enabled = false }
}

# -----------------------------------------------------------------------------
# Profile
# -----------------------------------------------------------------------------
# `response_export_values` is set from the first release, so it never changes on
# an existing profile — a change to it alone is a PUT of the unchanged body.

resource "azapi_resource" "this" {
  location  = "global"
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Cdn/profiles@2025-12-01"
  body = {
    properties = local.profile_properties
    sku = {
      name = var.sku
    }
  }
  response_export_values = {
    front_door_id = "properties.frontDoorId"
  }
  tags = var.tags

  dynamic "identity" {
    for_each = local.identity_type == null ? [] : [local.identity_type]
    content {
      type         = identity.value
      identity_ids = var.managed_identities.user_assigned_resource_ids
    }
  }
}

# -----------------------------------------------------------------------------
# Lock
# -----------------------------------------------------------------------------
# A `ReadOnly` lock on the profile blocks writes to its children too — every
# origin group, origin, endpoint, route and security policy in it.

resource "azapi_resource" "lock" {
  count = var.lock != null ? 1 : 0

  name      = coalesce(var.lock.name, "lock-${var.name}")
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Authorization/locks@2020-05-01"
  body = {
    properties = {
      level = var.lock.kind
      notes = var.lock.kind == "CanNotDelete" ? "Cannot be deleted." : "Cannot be modified."
    }
  }
}

# -----------------------------------------------------------------------------
# Role assignments
# -----------------------------------------------------------------------------
# AzAPI has no equivalent of azurerm's `role_definition_name`, so role names are
# resolved against a subscription-scope listing, as the AVM interfaces module
# does.
#
# Assignment names are random UUIDs. ARM makes the name the resource identity,
# so deriving it from the principal would let an unknown-at-plan-time principal
# ID force a replacement. `name` is exposed for callers adopting an existing
# assignment.

data "azapi_resource_list" "role_definitions" {
  count = length(local.role_definition_names) > 0 ? 1 : 0

  parent_id = local.provider_subscription_resource_id
  type      = "Microsoft.Authorization/roleDefinitions@2022-04-01"
  response_export_values = {
    results = "value[].{id: id, role_name: properties.roleName}"
  }
}

resource "random_uuid" "role_assignment_name" {
  for_each = var.role_assignments
}

resource "azapi_resource" "role_assignments" {
  for_each = var.role_assignments

  name      = coalesce(each.value.name, random_uuid.role_assignment_name[each.key].result)
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  body = {
    properties = {
      condition                          = each.value.condition
      conditionVersion                   = each.value.condition_version
      delegatedManagedIdentityResourceId = each.value.delegated_managed_identity_resource_id
      description                        = each.value.description
      principalId                        = each.value.principal_id
      principalType                      = each.value.principal_type
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
        role_assignments["${each.key}"] names the role "${each.value.role_definition_id_or_name}",
        which matched no role definition.

        Pass a role's display name exactly as Azure spells it, or a full
        role-definition resource ID. Names resolve against the roleDefinitions
        catalogue of the provider's subscription, so a CUSTOM role defined in a
        different subscription is not listed there and must be passed as an ID.
      EOT
    }
  }
}

# -----------------------------------------------------------------------------
# Diagnostic settings
# -----------------------------------------------------------------------------
# `Microsoft.Insights/diagnosticSettings` has never shipped a stable API version;
# 2021-05-01-preview is the newest and what AVM uses.

resource "azapi_resource" "diagnostic_settings" {
  for_each = var.diagnostic_settings

  name      = coalesce(each.value.name, each.key)
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
  body = {
    properties = {
      eventHubAuthorizationRuleId = each.value.event_hub_authorization_rule_resource_id
      eventHubName                = each.value.event_hub_name
      logAnalyticsDestinationType = each.value.log_analytics_destination_type
      logs = concat(
        [for category, enabled in each.value.log_categories : {
          category        = category
          categoryGroup   = null
          enabled         = enabled
          retentionPolicy = local.diagnostic_retention_policy
        }],
        [for group, enabled in each.value.log_groups : {
          category        = null
          categoryGroup   = group
          enabled         = enabled
          retentionPolicy = local.diagnostic_retention_policy
        }],
      )
      marketplacePartnerId = each.value.marketplace_partner_resource_id
      metrics = [for category, enabled in each.value.metric_categories : {
        category        = category
        enabled         = enabled
        retentionPolicy = local.diagnostic_retention_policy
      }]
      storageAccountId = each.value.storage_account_resource_id
      workspaceId      = each.value.workspace_resource_id
    }
  }
}
