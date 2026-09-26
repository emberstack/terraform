# =============================================================================
# AZURE FIREWALL (Microsoft.Network/azureFirewalls)
# =============================================================================
# A policy-managed firewall in a virtual network (`AZFW_VNet`). Rules live in a
# firewall policy — `azure-res-network-firewallpolicy` — which this module only
# references: a policy is its own resource and may serve several firewalls.
# Classic, firewall-embedded rule collections and the Virtual WAN form
# (`AZFW_Hub`) are not modelled.
#
# The data-plane public IPs are passed in, since they are usually owned with the
# rest of an estate's addresses and referenced by DNAT rules elsewhere. The
# management public IP is created here: it serves nothing but the firewall's
# own management traffic, so it has no life of its own.
#
# ARM returns `zones` in an order of its own — ["2", "3", "1"] for a request of
# ["1", "2", "3"] — and azapi compares a list of strings position by position,
# so the order it sent would diff against the order it got back on every plan.
# Zones cannot change once the resource exists, so both the firewall and its
# management public IP take `body.zones` from state after creation; a write
# then resends ARM's own ordering of the same set.
#
# Inputs mirror the AVM `Azure/avm-res-network-azurefirewall/azurerm` names
# where they overlap, over a `resource_group_name` like the rest of this family.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The subscription the provider is configured against. Used to list the
  # roleDefinitions catalogue. Built-in roles are present in every subscription,
  # so this resolves any built-in name; a CUSTOM role defined in a different
  # subscription is not in this listing and must be passed as a resource ID.
  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  resource_group_resource_id        = "${local.provider_subscription_resource_id}/resourceGroups/${var.resource_group_name}"

  primary_ip_configuration_key = one([for key, config in var.ip_configurations : key if config.primary])

  # The primary configuration first, then the rest by key. Items are matched to
  # ARM's copy by name, so the order is not what keeps the plan quiet; it keeps
  # the configuration holding the subnet first whatever the keys sort to.
  ip_configuration_keys = concat(
    [local.primary_ip_configuration_key],
    sort([for key in keys(var.ip_configurations) : key if key != local.primary_ip_configuration_key]),
  )

  management = var.firewall_management_ip_configuration
  management_public_ip = local.management == null ? null : merge(local.management.public_ip, {
    name = coalesce(local.management.public_ip.name, "${var.name}-mgmt-pip")
  })

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
# Management public IP
# -----------------------------------------------------------------------------

resource "azapi_resource" "management_public_ip" {
  count = local.management == null ? 0 : 1

  location  = var.location
  name      = local.management_public_ip.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Network/publicIPAddresses@2025-07-01"
  body = {
    properties = {
      ddosSettings = {
        ddosProtectionPlan = local.management_public_ip.ddos_protection_plan_resource_id == null ? null : {
          id = local.management_public_ip.ddos_protection_plan_resource_id
        }
        protectionMode = local.management_public_ip.ddos_protection_mode
      }
      publicIPAllocationMethod = "Static"
    }
    sku = {
      name = "Standard"
      tier = "Regional"
    }
    # A non-zonal address carries no `zones` at all; an empty list would be sent
    # as a request for one.
    zones = length(local.management_public_ip.zones) > 0 ? local.management_public_ip.zones : null
  }
  # `zones` and the DDoS plan are null when unused. Dropping the nulls keeps them
  # out of the request and stops ARM's response from diffing against them.
  ignore_null_property = true
  response_export_values = {
    ip_address = "properties.ipAddress"
  }
  tags = coalesce(local.management_public_ip.tags, var.tags)

  lifecycle {
    # See the banner: ARM reorders zones, and they cannot change in place.
    ignore_changes = [body.zones]
  }
}

# -----------------------------------------------------------------------------
# Firewall
# -----------------------------------------------------------------------------

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Network/azureFirewalls@2025-07-01"
  body = {
    properties = {
      firewallPolicy = {
        id = var.firewall_policy_id
      }
      ipConfigurations = [
        for key in local.ip_configuration_keys : {
          name = key
          properties = {
            publicIPAddress = {
              id = var.ip_configurations[key].public_ip_address_resource_id
            }
            subnet = key == local.primary_ip_configuration_key ? { id = var.subnet_resource_id } : null
          }
        }
      ]
      managementIpConfiguration = local.management == null ? null : {
        name = local.management.name
        properties = {
          publicIPAddress = {
            id = azapi_resource.management_public_ip[0].id
          }
          subnet = {
            id = local.management.subnet_resource_id
          }
        }
      }
      sku = {
        # See the banner: only the virtual-network form is modelled.
        name = "AZFW_VNet"
        tier = var.firewall_sku_tier
      }
      # Only classic, firewall-embedded rules read this; with a policy attached,
      # the policy's threat intelligence mode applies. It is still stored, so it
      # is sent as `Alert` — what the azurerm provider writes by default — and a
      # write leaves an existing firewall's value where it was.
      threatIntelMode = "Alert"
    }
    zones = length(var.firewall_zones) > 0 ? var.firewall_zones : null
  }
  # The subnet of a non-primary configuration, the management configuration and
  # zones are null when unused. Dropping the nulls keeps them out of the request
  # and stops ARM's response from diffing against them.
  ignore_null_property = true
  # Only the read-only attributes exposed as outputs.
  response_export_values = {
    ip_configurations = "properties.ipConfigurations[].{name: name, private_ip_address: properties.privateIPAddress}"
  }
  tags = var.tags

  timeouts {
    create = var.timeouts.create
    delete = var.timeouts.delete
    read   = var.timeouts.read
    update = var.timeouts.update
  }

  lifecycle {
    # See the banner: ARM reorders zones, and they cannot change in place.
    ignore_changes = [body.zones]
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
