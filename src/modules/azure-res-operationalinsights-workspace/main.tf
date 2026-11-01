# =============================================================================
# AZURE LOG ANALYTICS WORKSPACE (Microsoft.OperationalInsights/workspaces)
# =============================================================================
# A workspace with its tightly-coupled children: the workspace transformation
# DCR (ingestion-time KQL per table) and the workspace's link to it, Sentinel
# onboarding, linked storage accounts and role assignments.
#
# The DCR link cannot live in the workspace body. The DCR names the workspace as
# its destination, so the workspace has to exist first, and ARM resolves the
# destination when the DCR is written. The link is therefore set afterwards with
# `azapi_update_resource`, which reads the workspace and writes it back with the
# link merged in. A workspace PUT from this module does not carry the link, so
# the link resource is re-run whenever the workspace changes
# (`replace_triggered_by`), restoring it in the same apply.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The input stays a plain resource group name (AVM's shape); the subscription
  # comes from the configured provider, so an aliased or multi-subscription
  # caller still lands in the right place.
  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  resource_group_resource_id        = "${local.provider_subscription_resource_id}/resourceGroups/${var.resource_group_name}"

  identity_type = (
    var.managed_identities.system_assigned ? "SystemAssigned" :
    length(var.managed_identities.user_assigned_resource_ids) > 0 ? "UserAssigned" :
    null
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
}

# -----------------------------------------------------------------------------
# Workspace
# -----------------------------------------------------------------------------

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.OperationalInsights/workspaces@2025-07-01"
  body = {
    properties = {
      features = {
        disableLocalAuth                            = !var.local_authentication_enabled
        enableLogAccessUsingOnlyResourcePermissions = var.allow_resource_only_permissions
      }
      forceCmkForQuery                = var.cmk_for_query_forced
      publicNetworkAccessForIngestion = var.public_network_access_for_ingestion
      publicNetworkAccessForQuery     = var.public_network_access_for_query
      retentionInDays                 = var.retention_in_days
      sku = {
        name = var.sku
      }
      workspaceCapping = {
        dailyQuotaGb = var.daily_quota_gb
      }
    }
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
# Workspace transformation DCR and the workspace's link to it
# -----------------------------------------------------------------------------
# One data flow per table, in table-name order. Each flow reads the table's
# `Microsoft-Table-<name>` stream and writes it back to the workspace through the
# single `workspace` destination, which is what makes it a transformation.

resource "azapi_resource" "data_collection_rule" {
  count = var.workspace_transforms == null ? 0 : 1

  location  = var.location
  name      = var.workspace_transforms.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Insights/dataCollectionRules@2024-03-11"
  body = {
    kind = "WorkspaceTransforms"
    properties = {
      dataFlows = [
        for table, transform in var.workspace_transforms.table_transforms : {
          destinations = ["workspace"]
          streams      = ["Microsoft-Table-${table}"]
          transformKql = transform.transform_kql
        }
      ]
      description = var.workspace_transforms.description
      destinations = {
        logAnalytics = [
          {
            name                = "workspace"
            workspaceResourceId = azapi_resource.this.id
          },
        ]
      }
    }
  }
  tags = var.tags
}

resource "azapi_update_resource" "default_data_collection_rule" {
  count = var.workspace_transforms == null ? 0 : 1

  resource_id = azapi_resource.this.id
  type        = "Microsoft.OperationalInsights/workspaces@2025-07-01"
  body = {
    properties = {
      defaultDataCollectionRuleResourceId = azapi_resource.data_collection_rule[0].id
    }
  }

  lifecycle {
    # See the banner: a workspace write sends a body without the link.
    replace_triggered_by = [azapi_resource.this]
  }
}

# -----------------------------------------------------------------------------
# Microsoft Sentinel onboarding
# -----------------------------------------------------------------------------

resource "azapi_resource" "sentinel_onboarding" {
  count = var.sentinel_onboarding_enabled ? 1 : 0

  name      = "default"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.SecurityInsights/onboardingStates@2025-09-01"
  body = {
    properties = {}
  }
}

# -----------------------------------------------------------------------------
# Linked storage accounts
# -----------------------------------------------------------------------------
# Keyed by data source type; ARM uses the type as the child resource name.

resource "azapi_resource" "linked_storage_accounts" {
  for_each = var.linked_storage_accounts

  name      = each.key
  parent_id = azapi_resource.this.id
  type      = "Microsoft.OperationalInsights/workspaces/linkedStorageAccounts@2025-07-01"
  body = {
    properties = {
      storageAccountIds = each.value
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
