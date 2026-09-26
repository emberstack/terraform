# =============================================================================
# ROUTE SERVER (Microsoft.Network/virtualHubs)
# =============================================================================
# ARM models a route server as a virtual hub with no virtual WAN: the hub
# itself, an `ipConfigurations` child that places it in RouteServerSubnet, and
# `bgpConnections` children for its peers. The hub and its IP configuration are
# one deployable thing and live here; BGP connections are usually owned by the
# configuration that owns the NVA, so they live in `modules/bgp-connection`.
#
# The public IP is created here too. Azure requires one for the route server to
# reach its management service, and it serves nothing else, so it has no life of
# its own — the same reasoning that puts a private endpoint inside the redis
# module.
#
# Inputs mirror the AVM `Azure/avm-ptn-network-routeserver/azurerm` names where
# they overlap, over a `resource_group_name` like the rest of this family.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The subscription the provider is configured against. Used to list the
  # roleDefinitions catalogue. Built-in roles are present in every subscription,
  # so this resolves any built-in name; a CUSTOM role defined in a different
  # subscription is not in this listing and must be passed as a resource ID.
  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  resource_group_resource_id        = "${local.provider_subscription_resource_id}/resourceGroups/${var.resource_group_name}"

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

  # ARM stamps `retentionPolicy` onto every log and metric entry it returns,
  # years after retention moved to the workspace. azapi compares arrays
  # wholesale rather than per-property, so one entry missing it - or one
  # category ARM materialised that the config never sent - makes the whole
  # diagnostic setting diff on every plan, forever.
  diagnostic_retention_policy = { days = 0, enabled = false }
}

# -----------------------------------------------------------------------------
# Public IP
# -----------------------------------------------------------------------------

resource "azapi_resource" "public_ip" {
  location  = var.location
  name      = coalesce(var.routeserver_public_ip_config.name, "${var.name}-pip")
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Network/publicIPAddresses@2025-07-01"
  body = {
    properties = {
      ddosSettings = {
        ddosProtectionPlan = var.routeserver_public_ip_config.ddos_protection_plan_resource_id == null ? null : {
          id = var.routeserver_public_ip_config.ddos_protection_plan_resource_id
        }
        protectionMode = var.routeserver_public_ip_config.ddos_protection_mode
      }
      publicIPAllocationMethod = "Static"
    }
    sku = {
      name = "Standard"
      tier = "Regional"
    }
    # A non-zonal address carries no `zones` at all; an empty list would be sent
    # as a request for one.
    zones = length(var.routeserver_public_ip_config.zones) > 0 ? var.routeserver_public_ip_config.zones : null
  }
  # `zones` and the DDoS plan are null when unused. Dropping the nulls keeps them
  # out of the request and stops ARM's response from diffing against them.
  ignore_null_property = true
  response_export_values = {
    ip_address = "properties.ipAddress"
  }
  tags = coalesce(var.routeserver_public_ip_config.tags, var.tags)
}

# -----------------------------------------------------------------------------
# Route server
# -----------------------------------------------------------------------------
# `kind: RouteServer` in ARM's response is read-only portal metadata, and the
# router's ASN and IPs are assigned by Azure. None of them is sent.

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Network/virtualHubs@2025-07-01"
  body = {
    properties = {
      allowBranchToBranchTraffic = var.enable_branch_to_branch
      hubRoutingPreference       = var.hub_routing_preference
      # The only SKU a route server has.
      sku = "Standard"
      virtualRouterAutoScaleConfiguration = {
        minCapacity = var.routing_infrastructure_units
      }
    }
  }
  # Only the read-only attributes exposed as outputs.
  response_export_values = {
    routing_state      = "properties.routingState"
    virtual_router_asn = "properties.virtualRouterAsn"
    virtual_router_ips = "properties.virtualRouterIps"
  }
  tags = var.tags

  timeouts {
    create = var.timeouts.create
    delete = var.timeouts.delete
    read   = var.timeouts.read
    update = var.timeouts.update
  }
}

# -----------------------------------------------------------------------------
# IP configuration
# -----------------------------------------------------------------------------
# Part of the documented route server deployment, so it carries the same
# timeouts as the hub.

resource "azapi_resource" "ip_configuration" {
  name      = var.ip_configuration_name
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Network/virtualHubs/ipConfigurations@2025-07-01"
  body = {
    properties = {
      # Azure assigns the router's two peering addresses from RouteServerSubnet
      # (`virtualRouterIps`); the configuration asks for no address of its own.
      privateIPAllocationMethod = "Dynamic"
      publicIPAddress = {
        id = azapi_resource.public_ip.id
      }
      subnet = {
        id = var.subnet_resource_id
      }
    }
  }

  timeouts {
    create = var.timeouts.create
    delete = var.timeouts.delete
    read   = var.timeouts.read
    update = var.timeouts.update
  }
}

# -----------------------------------------------------------------------------
# Lock
# -----------------------------------------------------------------------------
# Taken after the IP configuration exists: a ReadOnly lock on the hub blocks
# writes to its children, and the graph does not otherwise order the two.

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

  depends_on = [azapi_resource.ip_configuration]
}

# -----------------------------------------------------------------------------
# Role assignments
# -----------------------------------------------------------------------------
# AzAPI has no equivalent of azurerm's `role_definition_name`, so role names are
# resolved against a subscription-scope listing, as the AVM interfaces module
# does.

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
# 2021-05-01-preview is the newest and what AVM uses. A route server has metrics
# and no log categories, so `logs` is always sent empty.

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
      logs                        = []
      marketplacePartnerId        = each.value.marketplace_partner_resource_id
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
