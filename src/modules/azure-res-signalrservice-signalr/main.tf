# =============================================================================
# AZURE SIGNALR SERVICE (Microsoft.SignalRService/signalR)
# =============================================================================
# AVM-style all-in-one module: SignalR service + identity + CORS + role
# assignments + network ACL + private endpoints + diagnostic settings.
#
# Mirrors the AVM input surface used by sibling emberstack modules
# (`azure-res-cache-redis`, etc.). The upstream AVM module
# `Azure/avm-res-signalrservice-signalr/azurerm` is currently *Proposed*
# and not yet published — this module fills the gap.
# =============================================================================

locals {
  # parent_id is the RG resource ID; azurerm needs the name.
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
# SignalR Service
# -----------------------------------------------------------------------------

resource "azurerm_signalr_service" "this" {
  name                = var.name
  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = var.tags

  sku {
    name     = var.sku_name
    capacity = var.sku_capacity
  }

  service_mode                             = var.service_mode
  public_network_access_enabled            = var.public_network_access_enabled
  local_auth_enabled                       = var.local_auth_enabled
  aad_auth_enabled                         = var.aad_auth_enabled
  tls_client_cert_enabled                  = var.tls_client_cert_enabled
  connectivity_logs_enabled                = var.connectivity_logs_enabled
  messaging_logs_enabled                   = var.messaging_logs_enabled
  http_request_logs_enabled                = var.http_request_logs_enabled
  serverless_connection_timeout_in_seconds = var.serverless_connection_timeout_in_seconds

  dynamic "live_trace" {
    for_each = var.live_trace == null ? [] : [var.live_trace]
    content {
      enabled                   = live_trace.value.enabled
      messaging_logs_enabled    = live_trace.value.messaging_logs_enabled
      connectivity_logs_enabled = live_trace.value.connectivity_logs_enabled
      http_request_logs_enabled = live_trace.value.http_request_logs_enabled
    }
  }

  dynamic "cors" {
    for_each = var.cors_allowed_origins == null ? [] : [var.cors_allowed_origins]
    content {
      allowed_origins = cors.value
    }
  }

  dynamic "identity" {
    for_each = local.identity_type == null ? [] : [local.identity_type]
    content {
      type         = identity.value
      identity_ids = local.has_user_assigned ? var.managed_identities.user_assigned_resource_ids : null
    }
  }

  dynamic "upstream_endpoint" {
    for_each = var.upstream_endpoints
    content {
      url_template              = upstream_endpoint.value.url_template
      category_pattern          = upstream_endpoint.value.category_pattern
      event_pattern             = upstream_endpoint.value.event_pattern
      hub_pattern               = upstream_endpoint.value.hub_pattern
      user_assigned_identity_id = upstream_endpoint.value.user_assigned_identity_id
    }
  }
}

# -----------------------------------------------------------------------------
# Lock
# -----------------------------------------------------------------------------

resource "azurerm_management_lock" "this" {
  count = var.lock != null ? 1 : 0

  name       = coalesce(var.lock.name, "lock-${var.name}")
  scope      = azurerm_signalr_service.this.id
  lock_level = var.lock.kind
  notes      = var.lock.kind == "CanNotDelete" ? "Cannot be deleted." : "Cannot be modified."
}

# -----------------------------------------------------------------------------
# Role assignments (service-scoped)
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope                                  = azurerm_signalr_service.this.id
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
# Diagnostic settings
# -----------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = var.diagnostic_settings

  name                           = coalesce(each.value.name, each.key)
  target_resource_id             = azurerm_signalr_service.this.id
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
    private_connection_resource_id = azurerm_signalr_service.this.id
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

# -----------------------------------------------------------------------------
# Network ACL
# -----------------------------------------------------------------------------
# A SignalR service has at most one network ACL. Managed as a sibling resource
# because per-PE rules need PE IDs (cyclical if inlined in the service body).
# -----------------------------------------------------------------------------

resource "azurerm_signalr_service_network_acl" "this" {
  count = var.network_acl != null ? 1 : 0

  signalr_service_id = azurerm_signalr_service.this.id
  default_action     = var.network_acl.default_action

  dynamic "public_network" {
    for_each = var.network_acl.public_network != null ? [var.network_acl.public_network] : []
    content {
      allowed_request_types = public_network.value.allowed_request_types
      denied_request_types  = public_network.value.denied_request_types
    }
  }

  dynamic "private_endpoint" {
    for_each = var.network_acl.private_endpoints
    content {
      id                    = azurerm_private_endpoint.this[private_endpoint.key].id
      allowed_request_types = private_endpoint.value.allowed_request_types
      denied_request_types  = private_endpoint.value.denied_request_types
    }
  }
}

