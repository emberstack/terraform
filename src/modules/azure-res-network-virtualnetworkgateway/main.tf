# =============================================================================
# VIRTUAL NETWORK GATEWAY (Microsoft.Network/virtualNetworkGateways)
# =============================================================================
# A VPN or ExpressRoute gateway in an existing GatewaySubnet, on public IP
# addresses owned elsewhere. The AzAPI AVM module for this resource is still an
# unimplemented template, so input names follow the archived
# `Azure/avm-ptn-vnetgateway/azurerm` where the two overlap — `sku`, `type`,
# the `vpn_*` settings, `ip_configurations` — over a `resource_group_name` like
# the rest of this family.
#
# ARM writes are full replaces, and this body models site-to-site and BGP only.
# Point-to-site (`vpnClientConfiguration`), NAT rules, policy groups, custom
# routes, a default site and DNS forwarding are never sent, so a gateway carrying
# any of them must not be managed here: the next write replaces the body without
# them.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The subscription the provider is configured against. Used to list the
  # roleDefinitions catalogue. Built-in roles are present in every subscription,
  # so this resolves any built-in name; a CUSTOM role defined in a different
  # subscription is not in this listing and must be passed as a resource ID.
  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  resource_group_resource_id        = "${local.provider_subscription_resource_id}/resourceGroups/${var.resource_group_name}"

  # Built rather than read from the resource: each BGP peering address names its
  # IP configuration by ID inside the gateway's own body, and a body cannot
  # reference the resource it is creating.
  gateway_resource_id = "${local.resource_group_resource_id}/providers/Microsoft.Network/virtualNetworkGateways/${var.name}"

  # ARM returns one peering address per IP configuration. Unlike
  # `ipConfigurations`, these entries carry no `name`, so azapi pairs the sent and
  # returned lists by position — both are built from the same map, in the same
  # key order, to keep that pairing aligned. Lists of different lengths are
  # compared wholesale, read-only properties included, and diff on every plan.
  bgp_peering_addresses = [
    for key, config in var.ip_configurations : {
      customBgpIpAddresses = config.apipa_addresses
      ipconfigurationId    = "${local.gateway_resource_id}/ipConfigurations/${key}"
    }
  ]

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
# Virtual network gateway
# -----------------------------------------------------------------------------

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Network/virtualNetworkGateways@2025-07-01"
  body = {
    properties = {
      activeActive           = var.vpn_active_active_enabled
      allowRemoteVnetTraffic = var.express_route_remote_vnet_traffic_enabled
      allowVirtualWanTraffic = var.express_route_virtual_wan_traffic_enabled
      bgpSettings = var.vpn_bgp_settings == null ? null : {
        asn                 = var.vpn_bgp_settings.asn
        bgpPeeringAddresses = local.bgp_peering_addresses
        peerWeight          = var.vpn_bgp_settings.peer_weight
      }
      disableIPSecReplayProtection    = !var.vpn_ip_sec_replay_protection_enabled
      enableBgp                       = var.vpn_bgp_enabled
      enableBgpRouteTranslationForNat = var.vpn_bgp_route_translation_for_nat_enabled
      enablePrivateIpAddress          = var.vpn_private_ip_address_enabled
      gatewayType                     = var.type
      ipConfigurations = [
        for key, config in var.ip_configurations : {
          name = key
          properties = {
            # The service accepts no other value for a gateway IP configuration.
            # Exposing it would offer a choice that does not exist.
            privateIPAllocationMethod = "Dynamic"
            publicIPAddress = {
              id = config.public_ip_address_resource_id
            }
            subnet = {
              id = var.subnet_resource_id
            }
          }
        }
      ]
      sku = {
        name = var.sku
        # Every gateway SKU's tier is spelled the same as its name — the two REST
        # enums are identical.
        tier = var.sku
      }
      # The REST specification requires `None` on anything but a VPN gateway.
      vpnGatewayGeneration = var.type == "Vpn" ? var.vpn_generation : "None"
      vpnType              = var.vpn_type
    }
  }
  # `bgpSettings` is null when `vpn_bgp_settings` is. Dropping the null keeps it
  # out of the request, so ARM keeps its default ASN, and stops the populated
  # value ARM returns from diffing against it.
  ignore_null_property = true
  # Only the read-only attributes exposed as outputs.
  response_export_values = {
    bgp_asn               = "properties.bgpSettings.asn"
    bgp_peering_addresses = "properties.bgpSettings.bgpPeeringAddresses[].{ip_configuration_id: ipconfigurationId, default_ip_addresses: defaultBgpIpAddresses, custom_ip_addresses: customBgpIpAddresses, tunnel_ip_addresses: tunnelIpAddresses}"
    ip_configurations     = "properties.ipConfigurations[].{name: name, private_ip_address: properties.privateIPAddress}"
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
