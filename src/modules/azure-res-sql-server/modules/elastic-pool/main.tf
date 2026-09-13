# =============================================================================
# AZURE SQL ELASTIC POOL (Microsoft.Sql/servers/elasticPools)
# =============================================================================
# A submodule rather than a collection on the parent: pools outlive individual
# deployments of the server config, and a team that owns a pool is frequently
# not the team that owns the server.
#
# `max_size_gb` and the SKU are the two inputs that reject silently-wrong
# values at ARM rather than at plan, because what a tier accepts varies by
# region and offer. `az sql elastic-pool list-editions -l <location> -o table`
# is the authoritative list for a subscription.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # ARM takes the storage limit in bytes. Azure calls the unit "GB" throughout
  # the portal and CLI but means GiB, so the factor is 1024^3 - 100 GB is
  # 107374182400 bytes, not 100000000000.
  max_size_bytes = var.max_size_gb == null ? null : var.max_size_gb * 1024 * 1024 * 1024

  # Built-in roles are present in every subscription, so this resolves any
  # built-in name; a CUSTOM role defined in a different subscription is not in
  # this listing and must be passed as a resource ID.
  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"

  role_definition_names = [for v in values(var.role_assignments) : v.role_definition_id_or_name]

  role_definition_name_to_resource_id = length(local.role_definition_names) > 0 ? {
    for definition in data.azapi_resource_list.role_definitions[0].output.results : definition.role_name => definition.id
  } : {}

  # Keyed by role, not by assignment key: a role definition is a property of the
  # ROLE, so two assignments naming the same role share one entry. An entry that
  # is already a resource ID falls through the lookup untouched.
  role_definition_resource_ids = {
    for name in toset(local.role_definition_names) :
    name => lookup(local.role_definition_name_to_resource_id, name, name)
  }
}

# -----------------------------------------------------------------------------
# Elastic pool
# -----------------------------------------------------------------------------
# `perDatabaseSettings` is always sent. ARM materialises it with the tier's own
# floor and ceiling when omitted, so leaving it out of a full-replace update
# would silently widen what a single database may consume.

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = var.sql_server_resource_id
  type      = "Microsoft.Sql/servers/elasticPools@2025-01-01"
  body = {
    properties = {
      autoPauseDelay               = var.auto_pause_delay
      availabilityZone             = var.availability_zone
      highAvailabilityReplicaCount = var.high_availability_replica_count
      licenseType                  = var.license_type
      maintenanceConfigurationId   = var.maintenance_configuration_resource_id
      maxSizeBytes                 = local.max_size_bytes
      minCapacity                  = var.min_capacity
      perDatabaseSettings = {
        maxCapacity = var.per_database_settings.max_capacity
        minCapacity = var.per_database_settings.min_capacity
      }
      preferredEnclaveType = var.preferred_enclave_type
      zoneRedundant        = var.zone_redundant
    }
    sku = {
      capacity = var.sku.capacity
      family   = var.sku.family
      name     = var.sku.name
      size     = var.sku.size
      tier     = var.sku.tier
    }
  }
  tags = var.tags

  # ARM materialises several of the nulls above rather than omitting them -
  # `autoPauseDelay` comes back as -1 on a provisioned pool, `minCapacity` as 0.
  # Comparing those against the configured nulls is a diff no apply can settle.
  ignore_null_property = true

  lifecycle {
    precondition {
      # Zone redundancy needs a tier that replicates. Basic and Standard DTU
      # pools do not, and ARM rejects the pair with an error that names the SKU
      # rather than the flag.
      condition     = !var.zone_redundant || !contains(["Basic", "Standard"], coalesce(var.sku.tier, "unset"))
      error_message = "zone_redundant is not supported on the Basic or Standard tiers - those pools have no replicas to spread."
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
