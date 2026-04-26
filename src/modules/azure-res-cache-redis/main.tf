# =============================================================================
# AZURE MANAGED REDIS (Microsoft.Cache/redisEnterprise)
# =============================================================================
# Mirrors the AVM `Azure/avm-res-cache-redisenterprise/azurerm` module's input
# surface as closely as possible, but uses the `azurerm` provider (not `azapi`)
# and exposes a few features the AVM module does not yet support:
#   - access_keys_authentication_enabled
#   - persistence_append_only_file_backup_frequency
#   - persistence_redis_database_backup_frequency
#   - geo_replication_group_name
#   - cluster-level diagnostic_settings (built-in, not a sidecar)
# =============================================================================

locals {
  # parent_id is the RG resource ID; azurerm needs the name + location.
  resource_group_name = element(split("/", var.parent_id), 4)

  # Identity assembly
  has_user_assigned   = length(var.managed_identities.user_assigned_resource_ids) > 0
  has_system_assigned = var.managed_identities.system_assigned
  identity_type = (
    local.has_system_assigned && local.has_user_assigned ? "SystemAssigned, UserAssigned" :
    local.has_system_assigned ? "SystemAssigned" :
    local.has_user_assigned ? "UserAssigned" :
    null
  )
}

# -----------------------------------------------------------------------------
# Cluster
# -----------------------------------------------------------------------------

resource "azurerm_managed_redis" "this" {
  name                = var.name
  resource_group_name = local.resource_group_name
  location            = var.location
  sku_name            = var.sku_name
  tags                = var.tags

  high_availability_enabled = var.high_availability == "Enabled"
  public_network_access     = var.public_network_access

  dynamic "identity" {
    for_each = local.identity_type == null ? [] : [local.identity_type]
    content {
      type         = identity.value
      identity_ids = local.has_user_assigned ? var.managed_identities.user_assigned_resource_ids : null
    }
  }

  dynamic "customer_managed_key" {
    for_each = var.customer_managed_key_encryption == null ? [] : [var.customer_managed_key_encryption]
    content {
      key_vault_key_id          = customer_managed_key.value.key_encryption_key_url
      user_assigned_identity_id = customer_managed_key.value.user_assigned_identity_resource_id
    }
  }

  default_database {
    client_protocol                               = var.enable_non_ssl_port ? "Plaintext" : "Encrypted"
    clustering_policy                             = var.clustering_policy
    eviction_policy                               = var.eviction_policy
    access_keys_authentication_enabled            = var.access_keys_authentication_enabled
    geo_replication_group_name                    = var.geo_replication_group_name
    persistence_append_only_file_backup_frequency = var.persistence_append_only_file_backup_frequency
    persistence_redis_database_backup_frequency   = var.persistence_redis_database_backup_frequency

    dynamic "module" {
      for_each = var.redis_modules
      content {
        name = module.value.name
        args = module.value.args
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Lock
# -----------------------------------------------------------------------------

resource "azurerm_management_lock" "this" {
  count = var.lock != null ? 1 : 0

  name       = coalesce(var.lock.name, "lock-${var.name}")
  scope      = azurerm_managed_redis.this.id
  lock_level = var.lock.kind
  notes      = var.lock.kind == "CanNotDelete" ? "Cannot be deleted." : "Cannot be modified."
}

# -----------------------------------------------------------------------------
# Role assignments (cluster-scoped)
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope                                  = azurerm_managed_redis.this.id
  principal_id                           = each.value.principal_id
  role_definition_name                   = startswith(each.value.role_definition_id_or_name, "/") ? null : each.value.role_definition_id_or_name
  role_definition_id                     = startswith(each.value.role_definition_id_or_name, "/") ? each.value.role_definition_id_or_name : null
  description                            = each.value.description
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
  principal_type                         = each.value.principal_type
}

# -----------------------------------------------------------------------------
# Diagnostic settings (cluster-scoped)
# -----------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = var.diagnostic_settings

  name                           = coalesce(each.value.name, each.key)
  target_resource_id             = azurerm_managed_redis.this.id
  log_analytics_workspace_id     = each.value.workspace_resource_id
  log_analytics_destination_type = each.value.workspace_resource_id == null ? null : each.value.log_analytics_destination_type
  storage_account_id             = each.value.storage_account_resource_id
  eventhub_authorization_rule_id = each.value.event_hub_authorization_rule_resource_id
  eventhub_name                  = each.value.event_hub_name
  partner_solution_id            = each.value.marketplace_partner_resource_id

  dynamic "enabled_log" {
    for_each = each.value.log_categories
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_log" {
    for_each = each.value.log_groups
    content {
      category_group = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = each.value.metric_categories
    content {
      category = enabled_metric.value
    }
  }
}

# -----------------------------------------------------------------------------
# Private endpoints
# -----------------------------------------------------------------------------

resource "azurerm_private_endpoint" "this" {
  for_each = var.private_endpoints

  name                          = coalesce(each.value.name, "${var.name}-pe-${each.key}")
  location                      = coalesce(each.value.location, var.location)
  resource_group_name           = coalesce(each.value.resource_group_name, local.resource_group_name)
  subnet_id                     = each.value.subnet_resource_id
  custom_network_interface_name = each.value.network_interface_name
  tags                          = each.value.tags

  private_service_connection {
    name                           = coalesce(each.value.private_service_connection_name, "${var.name}-psc-${each.key}")
    private_connection_resource_id = azurerm_managed_redis.this.id
    subresource_names              = [each.value.subresource_name]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_endpoints_manage_dns_zone_group && length(each.value.private_dns_zone_resource_ids) > 0 ? [1] : []
    content {
      name                 = each.value.private_dns_zone_group_name
      private_dns_zone_ids = each.value.private_dns_zone_resource_ids
    }
  }

  dynamic "ip_configuration" {
    for_each = each.value.ip_configurations
    content {
      name               = ip_configuration.value.name
      private_ip_address = ip_configuration.value.private_ip_address
      subresource_name   = coalesce(ip_configuration.value.subresource_name, each.value.subresource_name)
      member_name        = ip_configuration.value.member_name
    }
  }
}

# Per-PE locks
resource "azurerm_management_lock" "private_endpoint" {
  for_each = { for k, v in var.private_endpoints : k => v if v.lock != null }

  name       = coalesce(each.value.lock.name, "lock-${var.name}-pe-${each.key}")
  scope      = azurerm_private_endpoint.this[each.key].id
  lock_level = each.value.lock.kind
  notes      = each.value.lock.kind == "CanNotDelete" ? "Cannot be deleted." : "Cannot be modified."
}

# Per-PE role assignments — flattened across all (pe, ra) pairs.
locals {
  private_endpoint_role_assignments = merge([
    for pe_k, pe_v in var.private_endpoints : {
      for ra_k, ra_v in pe_v.role_assignments : "${pe_k}-${ra_k}" => merge(ra_v, { pe_key = pe_k })
    }
  ]...)
}

resource "azurerm_role_assignment" "private_endpoint" {
  for_each = local.private_endpoint_role_assignments

  scope                                  = azurerm_private_endpoint.this[each.value.pe_key].id
  principal_id                           = each.value.principal_id
  role_definition_name                   = startswith(each.value.role_definition_id_or_name, "/") ? null : each.value.role_definition_id_or_name
  role_definition_id                     = startswith(each.value.role_definition_id_or_name, "/") ? each.value.role_definition_id_or_name : null
  description                            = each.value.description
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
  principal_type                         = each.value.principal_type
}

# Per-PE application security group associations — flattened.
locals {
  private_endpoint_asg_associations = merge([
    for pe_k, pe_v in var.private_endpoints : {
      for asg_k, asg_v in pe_v.application_security_group_associations : "${pe_k}-${asg_k}" => {
        pe_key = pe_k
        asg_id = asg_v
      }
    }
  ]...)
}

resource "azurerm_private_endpoint_application_security_group_association" "private_endpoint" {
  for_each = local.private_endpoint_asg_associations

  private_endpoint_id           = azurerm_private_endpoint.this[each.value.pe_key].id
  application_security_group_id = each.value.asg_id
}

