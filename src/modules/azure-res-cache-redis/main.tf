# =============================================================================
# AZURE MANAGED REDIS (Microsoft.Cache/redisEnterprise)
# =============================================================================
# Mirrors the AVM `Azure/avm-res-cache-redisenterprise/azurerm` module's input
# surface as closely as possible, and exposes a few features AVM does not:
#   - access_keys_authentication_enabled
#   - persistence_append_only_file_backup_frequency
#   - persistence_redis_database_backup_frequency
#   - geo_replication_group_name
#   - cluster-level diagnostic_settings (built-in, not a sidecar)
#
# ARM models the cluster and its default database as two resources, so the
# `default_database` inputs land on a separate child rather than inline. The
# same is true of a private endpoint's DNS zone group. Application security
# group associations are the opposite case: ARM keeps them in the private
# endpoint body, so they are not a resource of their own.
#
# `kind` (v2) and `redundancyMode` are server-assigned and deliberately not sent.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The subscription the provider is configured against. Used to list the
  # roleDefinitions catalogue. Built-in roles are present in every subscription,
  # so this resolves any built-in name; a CUSTOM role defined in a different
  # subscription is not in this listing and must be passed as a resource ID.
  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"

  # The input stays a plain resource group name (AVM's shape); the subscription
  # comes from the configured provider, so an aliased or multi-subscription
  # caller still lands in the right place.
  resource_group_resource_id = "${local.provider_subscription_resource_id}/resourceGroups/${var.resource_group_name}"

  # A private endpoint must be created in the same subscription as the virtual
  # network it attaches to, while the private-link resource it targets may sit in
  # a different one (private-endpoint-overview, properties 4 and 5). So when an
  # endpoint supplies only `resource_group_name`, that group is resolved in the
  # SUBNET's subscription — not the cluster's and not the provider's.
  private_endpoint_subscription_resource_ids = {
    for k, v in var.private_endpoints : k => join("/", slice(split("/", v.subnet_resource_id), 0, 3))
  }

  has_user_assigned   = length(var.managed_identities.user_assigned_resource_ids) > 0
  has_system_assigned = var.managed_identities.system_assigned
  identity_type = (
    local.has_system_assigned && local.has_user_assigned ? "SystemAssigned, UserAssigned" :
    local.has_system_assigned ? "SystemAssigned" :
    local.has_user_assigned ? "UserAssigned" :
    null
  )

  # ARM spells this lower-camel, unlike the PascalCase used for the resource
  # identity `type` right above. `UserAssignedIdentity` is the only value the
  # variable's own validation accepts, so it is the only spelling to map; a
  # `systemAssignedIdentity` branch here would be unreachable code. If the
  # resource provider ever accepts the other spelling, widen the validation in
  # variables.tf and this local together.
  customer_managed_key_identity_type = (
    var.customer_managed_key_encryption == null ? null : "userAssignedIdentity"
  )

  role_definition_name_to_resource_id = length(local.all_role_assignments) > 0 ? {
    for definition in data.azapi_resource_list.role_definitions[0].output.results : definition.role_name => definition.id
  } : {}

  # Keyed by role name, not by assignment key — a role definition is per role, and
  # the same role may be assigned at both scopes. An entry that is already a
  # resource ID falls through the lookup untouched and maps to itself.
  role_definition_resource_ids = {
    for name in toset(concat(
      [for v in values(var.role_assignments) : v.role_definition_id_or_name],
      [for v in values(local.private_endpoint_role_assignments) : v.role_definition_id_or_name],
    )) : name => lookup(local.role_definition_name_to_resource_id, name, name)
  }

  # Per-PE role assignments, flattened across all (pe, ra) pairs.
  private_endpoint_role_assignments = merge([
    for pe_k, pe_v in var.private_endpoints : {
      for ra_k, ra_v in pe_v.role_assignments : "${pe_k}-${ra_k}" => merge(ra_v, { pe_key = pe_k })
    }
  ]...)

  # Only the length of this is read: it gates the roleDefinitions listing so the
  # data source is skipped when there is no assignment at either scope. A key
  # collision between the two keyspaces is harmless for that purpose.
  all_role_assignments = merge(var.role_assignments, local.private_endpoint_role_assignments)
}

# -----------------------------------------------------------------------------
# Cluster
# -----------------------------------------------------------------------------

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Cache/redisEnterprise@2025-07-01"
  body = {
    properties = {
      encryption = var.customer_managed_key_encryption == null ? {} : {
        customerManagedKeyEncryption = {
          keyEncryptionKeyIdentity = {
            identityType                   = local.customer_managed_key_identity_type
            userAssignedIdentityResourceId = var.customer_managed_key_encryption.user_assigned_identity_resource_id
          }
          keyEncryptionKeyUrl = var.customer_managed_key_encryption.key_encryption_key_url
        }
      }
      highAvailability    = var.high_availability
      minimumTlsVersion   = var.minimum_tls_version
      publicNetworkAccess = var.public_network_access
    }
    sku = {
      name = var.sku_name
    }
  }
  response_export_values = { host_name = "properties.hostName" }
  tags                   = var.tags

  dynamic "identity" {
    for_each = local.identity_type == null ? [] : [local.identity_type]
    content {
      type         = identity.value
      identity_ids = var.managed_identities.user_assigned_resource_ids
    }
  }
}

# -----------------------------------------------------------------------------
# Default database
# -----------------------------------------------------------------------------
# ARM keeps the database separate from the cluster. `redisVersion` and
# `deferUpgrade` are left to the service and not sent; `port` IS sent, for the
# same reason as `minimum_tls_version` — a full-replace write would otherwise
# reset it to the default and move the port clients connect to.

resource "azapi_resource" "database" {
  name      = "default"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Cache/redisEnterprise/databases@2025-07-01"
  body = {
    properties = {
      accessKeysAuthentication = var.access_keys_authentication_enabled ? "Enabled" : "Disabled"
      clientProtocol           = var.enable_non_ssl_port ? "Plaintext" : "Encrypted"
      clusteringPolicy         = var.clustering_policy
      evictionPolicy           = var.eviction_policy
      geoReplication = var.geo_replication_group_name == null ? null : {
        groupNickname = var.geo_replication_group_name
      }
      modules = [for m in var.redis_modules : {
        args = m.args
        name = m.name
      }]
      persistence = {
        aofEnabled   = var.persistence_append_only_file_backup_frequency != null
        aofFrequency = var.persistence_append_only_file_backup_frequency
        rdbEnabled   = var.persistence_redis_database_backup_frequency != null
        rdbFrequency = var.persistence_redis_database_backup_frequency
      }
      port = var.port
    }
  }
  response_export_values = { port = "properties.port" }
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
  count = length(local.all_role_assignments) > 0 ? 1 : 0

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

# -----------------------------------------------------------------------------
# Private endpoints
# -----------------------------------------------------------------------------
# `applicationSecurityGroups` live in the private endpoint body — ARM has no
# separate association resource for them.

resource "azapi_resource" "private_endpoint" {
  for_each = var.private_endpoints

  location  = coalesce(each.value.location, var.location)
  name      = coalesce(each.value.name, "${var.name}-pe-${each.key}")
  parent_id = each.value.resource_group_name == null ? local.resource_group_resource_id : "${local.private_endpoint_subscription_resource_ids[each.key]}/resourceGroups/${each.value.resource_group_name}"
  type      = "Microsoft.Network/privateEndpoints@2025-07-01"
  body = {
    properties = {
      applicationSecurityGroups = [
        for asg_id in values(each.value.application_security_group_associations) : { id = asg_id }
      ]
      customNetworkInterfaceName = each.value.network_interface_name
      ipConfigurations = [for ip in values(each.value.ip_configurations) : {
        name = ip.name
        properties = {
          groupId          = coalesce(ip.subresource_name, each.value.subresource_name)
          memberName       = ip.member_name
          privateIPAddress = ip.private_ip_address
        }
      }]
      privateLinkServiceConnections = [{
        name = coalesce(each.value.private_service_connection_name, "${var.name}-psc-${each.key}")
        properties = {
          groupIds             = [each.value.subresource_name]
          privateLinkServiceId = azapi_resource.this.id
        }
      }]
      subnet = {
        id = each.value.subnet_resource_id
      }
    }
  }
  # ARM returns "" for an unset customNetworkInterfaceName, which would diff
  # against the null this sends.
  ignore_null_property = true
  response_export_values = {
    custom_dns_configs = "properties.customDnsConfigs"
    network_interfaces = "properties.networkInterfaces"
  }
  tags = each.value.tags
}

# ARM models the DNS zone group as a child of the private endpoint. Each config
# is named after its zone, matching what the portal and azurerm produce.
resource "azapi_resource" "private_endpoint_dns_zone_group" {
  for_each = {
    for k, v in var.private_endpoints : k => v
    if var.private_endpoints_manage_dns_zone_group && length(v.private_dns_zone_resource_ids) > 0
  }

  name      = each.value.private_dns_zone_group_name
  parent_id = azapi_resource.private_endpoint[each.key].id
  type      = "Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2025-07-01"
  body = {
    properties = {
      privateDnsZoneConfigs = [for zone_id in each.value.private_dns_zone_resource_ids : {
        name = basename(zone_id)
        properties = {
          privateDnsZoneId = zone_id
        }
      }]
    }
  }
  response_export_values = { record_sets = "properties.privateDnsZoneConfigs[].recordSets[]" }
}

resource "azapi_resource" "private_endpoint_lock" {
  for_each = { for k, v in var.private_endpoints : k => v if v.lock != null }

  name      = coalesce(each.value.lock.name, "lock-${var.name}-pe-${each.key}")
  parent_id = azapi_resource.private_endpoint[each.key].id
  type      = "Microsoft.Authorization/locks@2020-05-01"
  body = {
    properties = {
      level = each.value.lock.kind
      notes = each.value.lock.kind == "CanNotDelete" ? "Cannot be deleted." : "Cannot be modified."
    }
  }
}

resource "random_uuid" "private_endpoint_role_assignment_name" {
  for_each = local.private_endpoint_role_assignments
}

resource "azapi_resource" "private_endpoint_role_assignments" {
  for_each = local.private_endpoint_role_assignments

  name      = coalesce(each.value.name, random_uuid.private_endpoint_role_assignment_name[each.key].result)
  parent_id = azapi_resource.private_endpoint[each.value.pe_key].id
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
}
