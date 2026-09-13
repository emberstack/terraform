# =============================================================================
# AZURE SQL DATABASE (Microsoft.Sql/servers/databases)
# =============================================================================
# A submodule rather than a collection on the parent: a database has its own
# lifecycle, its own owner, and - unlike the server - holds data, so it must be
# possible to manage one without the config that built the server around it.
#
# BACKUP RETENTION IS MODELLED HERE ON PURPOSE. Both policies are separate ARM
# child resources and are easy to leave unmanaged, which is how a database ends
# up with PITR only. That matters more than it sounds: deleting a SERVER deletes
# its databases AND their PITR backups, and they cannot be restored. LTR backups
# are the only class that survives, so `long_term_retention` is the difference
# between a recoverable database and an unrecoverable one.
#
# BOTH RETENTION POLICIES ARE SINGLETONS ARM CREATES with the database, so they
# are `azapi_update_resource`. Creating them fails a greenfield apply with
# "Resource already exists" - ARM got there first, with PITR at 7 days and LTR
# at `PT0S` everywhere, and the job here is to PATCH them into shape.
#
# `max_size_gb` and the SKU are rejected at ARM rather than at plan when wrong,
# because what a tier accepts varies by region and offer. Inside a pool both are
# governed by the pool instead - see the preconditions below.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # Built-in roles are present in every subscription, so this resolves any
  # built-in name; a CUSTOM role defined in a different subscription is not in
  # this listing and must be passed as a resource ID.
  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"

  in_elastic_pool = var.elastic_pool_resource_id != null

  # ARM takes the max size in bytes. Azure calls the unit "GB" throughout the
  # portal and CLI but means GiB, so the factor is 1024^3 - 250 GB is
  # 268435456000 bytes, not 250000000000.
  max_size_bytes = var.max_size_gb == null ? null : var.max_size_gb * 1024 * 1024 * 1024

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
# `sku` is omitted entirely for a pooled database. ARM derives it from the pool,
# and sending one alongside `elasticPoolId` is rejected.
#
# `collation` and `isLedgerOn` cannot be changed after creation. They are sent
# anyway rather than left out, so a caller who edits one gets an honest ARM
# error instead of a silently ignored change.

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = var.sql_server_resource_id
  type      = "Microsoft.Sql/servers/databases@2025-01-01"
  body = {
    properties = {
      autoPauseDelay                   = var.auto_pause_delay
      availabilityZone                 = var.availability_zone
      catalogCollation                 = var.catalog_collation
      collation                        = var.collation
      elasticPoolId                    = var.elastic_pool_resource_id
      encryptionProtector              = try(var.customer_managed_key.key_vault_key_uri, null)
      encryptionProtectorAutoRotation  = try(var.customer_managed_key.auto_rotation_enabled, null)
      federatedClientId                = var.federated_client_id
      highAvailabilityReplicaCount     = var.high_availability_replica_count
      isLedgerOn                       = var.ledger_enabled
      licenseType                      = var.license_type
      maintenanceConfigurationId       = var.maintenance_configuration_resource_id
      maxSizeBytes                     = local.in_elastic_pool ? null : local.max_size_bytes
      minCapacity                      = var.min_capacity
      preferredEnclaveType             = var.preferred_enclave_type
      readScale                        = var.read_scale_enabled == null ? null : (var.read_scale_enabled ? "Enabled" : "Disabled")
      requestedBackupStorageRedundancy = var.backup_storage_redundancy
      zoneRedundant                    = var.zone_redundant
    }
    sku = local.in_elastic_pool ? null : {
      capacity = try(var.sku.capacity, null)
      family   = try(var.sku.family, null)
      name     = try(var.sku.name, null)
      tier     = try(var.sku.tier, null)
    }
  }
  tags = var.tags

  # ARM materialises most of the nulls above rather than omitting them -
  # `autoPauseDelay` returns -1, `minCapacity` returns 0 - so comparing them
  # against the configured nulls is a diff no apply can settle.
  ignore_null_property = true

  dynamic "identity" {
    for_each = length(var.managed_identities.user_assigned_resource_ids) > 0 ? ["UserAssigned"] : []
    content {
      type         = identity.value
      identity_ids = var.managed_identities.user_assigned_resource_ids
    }
  }

  lifecycle {
    precondition {
      # A pooled database takes its capacity from the pool. ARM rejects a `sku`
      # sent alongside `elasticPoolId`, with an error about the SKU rather than
      # about the pool.
      condition     = var.elastic_pool_resource_id == null || var.sku == null
      error_message = "sku must be null for a database in an elastic pool - the pool provides the capacity."
    }

    precondition {
      # The inverse: a standalone database has nothing to inherit from.
      condition     = var.elastic_pool_resource_id != null || var.sku != null
      error_message = "sku is required for a standalone database (one with no elastic_pool_resource_id)."
    }

    precondition {
      # Storage is a pool-level property for a pooled database.
      condition     = var.elastic_pool_resource_id == null || var.max_size_gb == null
      error_message = "max_size_gb must be null for a database in an elastic pool - the pool's own limit applies."
    }

    precondition {
      # Database-level CMK resolves the key through a user-assigned identity on
      # the DATABASE, which is separate from the server's. Without one the
      # create fails inside ARM with an error naming neither input.
      condition     = var.customer_managed_key == null || length(var.managed_identities.user_assigned_resource_ids) > 0
      error_message = "customer_managed_key requires managed_identities.user_assigned_resource_ids - database-level TDE resolves the key through a database identity, not the server's."
    }
  }
}

# -----------------------------------------------------------------------------
# Short-term retention (point-in-time restore)
# -----------------------------------------------------------------------------
# PITR backups die with the SERVER. "If you delete a server, all of its
# databases and their PITR backups are also deleted" - so this window protects
# against dropping a database, not against losing the server it lives on.

resource "azapi_update_resource" "short_term_retention" {
  count = var.short_term_retention != null ? 1 : 0

  name      = "default"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Sql/servers/databases/backupShortTermRetentionPolicies@2025-01-01"

  # PATCHed, not created: ARM gives every database this policy on day one, so a
  # create collides. `diffBackupIntervalInHours` is omitted rather than nulled
  # when unset - the default varies by tier and an omitted property is not
  # compared.
  body = {
    properties = merge(
      { retentionDays = var.short_term_retention.retention_days },
      var.short_term_retention.differential_backup_interval_in_hours == null ? {} : {
        diffBackupIntervalInHours = var.short_term_retention.differential_backup_interval_in_hours
      },
    )
  }
}

# -----------------------------------------------------------------------------
# Long-term retention
# -----------------------------------------------------------------------------
# The only backup class that survives deletion of the server. An all-zero policy
# (`PT0S` everywhere) is what Azure reports when LTR was never configured, and
# is indistinguishable from having none.

resource "azapi_update_resource" "long_term_retention" {
  count = var.long_term_retention != null ? 1 : 0

  name      = "default"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Sql/servers/databases/backupLongTermRetentionPolicies@2025-01-01"

  # PATCHed, not created: ARM gives every database this policy on day one, with
  # every field `PT0S`. Unset fields are sent AS `PT0S` rather than omitted -
  # that is ARM's own spelling of "no retention", so clearing a retention class
  # actually clears it instead of leaving the previous value in place.
  body = {
    properties = {
      monthlyRetention = coalesce(var.long_term_retention.monthly_retention, "PT0S")
      weeklyRetention  = coalesce(var.long_term_retention.weekly_retention, "PT0S")
      weekOfYear       = coalesce(var.long_term_retention.week_of_year, 0)
      yearlyRetention  = coalesce(var.long_term_retention.yearly_retention, "PT0S")
    }
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
      # An unresolved name falls through the `lookup` default and reaches ARM as
      # a bare string in `roleDefinitionId`, which fails with an error naming
      # neither the role nor this assignment. Resolved values are ARM IDs.
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
#
# `SQLSecurityAuditEvents` is a category HERE, not on the server. Server-level
# auditing writes its events to the `master` database's diagnostic setting, so
# shipping audit logs means pointing a setting on that database at the
# workspace - the server's own diagnostic settings will not carry them.

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
        [for category in each.value.log_categories : { category = category, enabled = true }],
        [for group in each.value.log_groups : { categoryGroup = group, enabled = true }],
      )
      marketplacePartnerId = each.value.marketplace_partner_resource_id
      metrics              = [for category in each.value.metric_categories : { category = category, enabled = true }]
      storageAccountId     = each.value.storage_account_resource_id
      workspaceId          = each.value.workspace_resource_id
    }
  }
}
