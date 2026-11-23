# =============================================================================
# AZURE SQL MANAGED INSTANCE DATABASE (Microsoft.Sql/managedInstances/databases)
# =============================================================================
# A submodule rather than a collection on the instance, for the same reason as
# `azure-res-sql-server/modules/database`: a database holds data and has its
# own lifecycle, so it must be manageable without the config that built the
# instance around it.
#
# BACKUP RETENTION IS THE MAIN REASON TO MANAGE ONE HERE. Both policies are
# separate ARM child resources that ARM creates with the database - PITR at 7
# days, LTR at `PT0S` everywhere - and are easy to leave that way. LTR backups
# are the only class that outlives the instance.
#
# BOTH POLICIES ARE SINGLETONS ARM CREATES, so they are `azapi_update_resource`.
# Creating them fails a greenfield apply with "Resource already exists".
#
# Only properties that describe the database itself are modelled. The
# restore/migration create modes (`createMode`, `sourceDatabaseId`,
# `storageContainerUri`, ...) are one-shot instructions, not state - sending
# them on every update would re-request the restore.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # Same reason as the logical-server database module: ARM stamps
  # `retentionPolicy` on every log and metric entry it returns, and azapi
  # compares the arrays wholesale.
  diagnostic_retention_policy = { days = 0, enabled = false }

  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"

  role_definition_names = [for v in values(var.role_assignments) : v.role_definition_id_or_name]

  role_definition_name_to_resource_id = length(local.role_definition_names) > 0 ? {
    for definition in data.azapi_resource_list.role_definitions[0].output.results : definition.role_name => definition.id
  } : {}

  role_definition_resource_ids = {
    for name in toset(local.role_definition_names) :
    name => lookup(local.role_definition_name_to_resource_id, name, name)
  }
}

# -----------------------------------------------------------------------------
# Database
# -----------------------------------------------------------------------------
# `collation`, `catalogCollation` and `isLedgerOn` cannot be changed after
# creation. They are sent anyway, so a caller who edits one gets an honest ARM
# error instead of a silently ignored change.

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = var.managed_instance_resource_id
  type      = "Microsoft.Sql/managedInstances/databases@2025-01-01"
  body = {
    properties = {
      catalogCollation = var.catalog_collation
      collation        = var.collation
      isLedgerOn       = var.ledger_enabled
    }
  }
  # Nothing is exported. The response carries `earliestRestorePoint`, which
  # advances on its own; stored in `output`, it fails any apply that outlasts a
  # tick of that clock with "Provider produced inconsistent result after apply".
  response_export_values = {}

  tags = var.tags

  ignore_null_property = true
}

# -----------------------------------------------------------------------------
# Short-term retention (point-in-time restore)
# -----------------------------------------------------------------------------
# A managed instance schedules its own differential backups (every 12 hours),
# so unlike a logical-server database only the window is configurable.

resource "azapi_update_resource" "short_term_retention" {
  count = var.short_term_retention != null ? 1 : 0

  name      = "default"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Sql/managedInstances/databases/backupShortTermRetentionPolicies@2025-01-01"

  body = {
    properties = {
      retentionDays = var.short_term_retention.retention_days
    }
  }
}

# -----------------------------------------------------------------------------
# Long-term retention
# -----------------------------------------------------------------------------
# The only backup class that survives deletion of the instance.
#
# Two resources, mirroring the logical-server database module: without a
# yearly backup ARM reads `weekOfYear` back as 0, yet a logical-server database
# rejects 0 on write. The no-yearly variant therefore sends 1 and ignores the
# field. Only one of the two exists at a time; switching between them is a
# state-only swap, since deleting an `azapi_update_resource` doesn't touch
# Azure.

resource "azapi_update_resource" "long_term_retention" {
  count = try(var.long_term_retention.yearly_retention, null) != null ? 1 : 0

  name      = "default"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Sql/managedInstances/databases/backupLongTermRetentionPolicies@2025-01-01"

  # Unset fields are sent AS `PT0S` rather than omitted - ARM's own spelling of
  # "no retention" - so clearing a class actually clears it.
  body = {
    properties = {
      monthlyRetention = coalesce(var.long_term_retention.monthly_retention, "PT0S")
      weeklyRetention  = coalesce(var.long_term_retention.weekly_retention, "PT0S")
      weekOfYear       = var.long_term_retention.week_of_year
      yearlyRetention  = var.long_term_retention.yearly_retention
    }
  }
}

resource "azapi_update_resource" "long_term_retention_without_yearly" {
  count = var.long_term_retention != null && try(var.long_term_retention.yearly_retention, null) == null ? 1 : 0

  name      = "default"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Sql/managedInstances/databases/backupLongTermRetentionPolicies@2025-01-01"

  body = {
    properties = {
      monthlyRetention = coalesce(var.long_term_retention.monthly_retention, "PT0S")
      weeklyRetention  = coalesce(var.long_term_retention.weekly_retention, "PT0S")
      weekOfYear       = 1
      yearlyRetention  = "PT0S"
    }
  }

  lifecycle {
    # Dotted path only: an index step into the dynamic `body` would ignore the
    # whole parent.
    ignore_changes = [body.properties.weekOfYear]
  }
}

# -----------------------------------------------------------------------------
# Lock
# -----------------------------------------------------------------------------

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
# Role names resolve against a subscription-scope listing; assignment names
# are random UUIDs so an unknown-at-plan-time principal cannot force a
# replacement. `name` is exposed for adopting an existing assignment.

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
# 2021-05-01-preview is the newest version `Microsoft.Insights/diagnosticSettings`
# has shipped.

resource "azapi_resource" "diagnostic_settings" {
  for_each = var.diagnostic_settings

  name      = coalesce(each.value.name, each.key)
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
  body = {
    properties = {
      eventHubAuthorizationRuleId = each.value.event_hub_authorization_rule_resource_id
      eventHubName                = each.value.event_hub_name
      logAnalyticsDestinationType = each.value.workspace_resource_id == null ? null : each.value.log_analytics_destination_type
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
