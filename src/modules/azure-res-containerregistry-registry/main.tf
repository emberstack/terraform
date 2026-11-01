# =============================================================================
# AZURE CONTAINER REGISTRY (Microsoft.ContainerRegistry/registries)
# =============================================================================
# Mirrors the AVM `Azure/avm-res-containerregistry-registry/azurerm` input
# surface where it can, and exposes a few things AVM does not:
#   - role_assignment_mode, pinned rather than left to the service default
#   - network_rule_bypass_allowed_for_tasks and the Entra-auth-as-ARM policy
#   - import_images, seeding images through ARM's importImage action
#
# Nothing here sets `response_export_values`. A change to it alone is a PUT of
# the unchanged body, so adopting an existing registry by `terraform import`
# would cost a write on every resource that carried one. The outputs are built
# from what ARM returns by default instead.
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
  # network it attaches to, while the registry it targets may sit in a different
  # one. So when an endpoint supplies only `resource_group_name`, that group is
  # resolved in the SUBNET's subscription — not the registry's and not the
  # provider's.
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

  premium = var.sku == "Premium"

  # ARM keys `keyVaultProperties.identity` by the identity's CLIENT ID, while the
  # input names it by resource ID like every other identity reference; the data
  # source below translates. A versionless key URI turns on ACR's own rotation
  # (`keyRotationEnabled`, read-only); a versioned one pins the key.
  encryption = var.customer_managed_key == null ? null : {
    keyVaultProperties = {
      identity      = data.azapi_resource.customer_managed_key_identity[0].output.client_id
      keyIdentifier = var.customer_managed_key.key_vault_key_uri
    }
    status = "enabled"
  }

  # Network rules, and the quarantine, retention and trust policies, are Premium
  # features. They are left out of the body on the other tiers rather than sent
  # in their disabled form.
  network_rule_set = !local.premium ? null : {
    defaultAction = var.network_rule_set.default_action
    ipRules       = [for ip in var.network_rule_set.ip_rules : { action = "Allow", value = ip }]
  }

  # Every policy is sent, the disabled ones included: an azapi update is a full
  # replace, so a policy left out could fall back to the service default on any
  # unrelated change.
  policies = merge(
    {
      azureADAuthenticationAsArmPolicy = { status = var.azure_ad_authentication_as_arm_policy_enabled ? "enabled" : "disabled" }
      exportPolicy                     = { status = var.export_policy_enabled ? "enabled" : "disabled" }
    },
    [for k, v in {
      quarantinePolicy = { status = var.quarantine_policy_enabled ? "enabled" : "disabled" }
      retentionPolicy  = { days = var.retention_policy.days, status = var.retention_policy.enabled ? "enabled" : "disabled" }
      trustPolicy      = { status = var.trust_policy_enabled ? "enabled" : "disabled", type = "Notary" }
    } : { (k) = v } if local.premium]...
  )

  registry_properties = merge(
    {
      adminUserEnabled                 = var.admin_enabled
      anonymousPullEnabled             = var.anonymous_pull_enabled
      dataEndpointEnabled              = var.data_endpoint_enabled
      networkRuleBypassAllowedForTasks = var.network_rule_bypass_allowed_for_tasks
      networkRuleBypassOptions         = var.network_rule_bypass_option
      policies                         = local.policies
      publicNetworkAccess              = var.public_network_access_enabled ? "Enabled" : "Disabled"
      roleAssignmentMode               = var.role_assignment_mode
      zoneRedundancy                   = var.zone_redundancy_enabled ? "Enabled" : "Disabled"
    },
    [for k, v in {
      encryption     = local.encryption
      networkRuleSet = local.network_rule_set
    } : { (k) = v } if v != null]...
  )

  # Every role this module assigns across both scopes, as the caller spelled it — a
  # display name or an ARM resource ID. Concatenated rather than merged: the two
  # keyspaces can collide (a registry-scope key `a-b` against the `<pe>-<ra>`
  # composite), and a merge would silently drop a role. Deduplication happens in
  # `role_definition_resource_ids`.
  role_definition_names = concat(
    [for v in values(var.role_assignments) : v.role_definition_id_or_name],
    [for v in values(local.private_endpoint_role_assignments) : v.role_definition_id_or_name],
  )

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

  # Per-PE role assignments, flattened across all (pe, ra) pairs.
  private_endpoint_role_assignments = merge([
    for pe_k, pe_v in var.private_endpoints : {
      # `ra_key` is carried alongside `pe_key` so outputs can regroup these by
      # endpoint and key them the way the caller wrote them, rather than exposing
      # the composite state-addressing key.
      for ra_k, ra_v in pe_v.role_assignments : "${pe_k}-${ra_k}" => merge(ra_v, { pe_key = pe_k, ra_key = ra_k })
    }
  ]...)

  # ARM materialises every category with a retention policy of its own, deprecated
  # and always off. Sent in full so the arrays compare equal; anything less leaves
  # the diagnostic setting diff on every plan.
  diagnostic_retention_policy = { days = 0, enabled = false }
}

# -----------------------------------------------------------------------------
# Registry
# -----------------------------------------------------------------------------

data "azapi_resource" "customer_managed_key_identity" {
  count = var.customer_managed_key == null ? 0 : 1

  resource_id            = var.customer_managed_key.user_assigned_identity_resource_id
  type                   = "Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30"
  response_export_values = { client_id = "properties.clientId" }
}

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.ContainerRegistry/registries@2025-11-01"
  body = {
    properties = local.registry_properties
    sku = {
      name = var.sku
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

  lifecycle {
    precondition {
      condition = local.premium || (
        var.customer_managed_key == null &&
        length(var.private_endpoints) == 0 &&
        length(var.georeplications) == 0 &&
        !var.data_endpoint_enabled &&
        !var.quarantine_policy_enabled &&
        !var.retention_policy.enabled &&
        !var.trust_policy_enabled
      )
      error_message = <<-EOT
        customer_managed_key, private_endpoints, georeplications, data_endpoint_enabled
        and the quarantine, retention and trust policies all require sku = "Premium".
      EOT
    }
  }
}

# -----------------------------------------------------------------------------
# Geo-replications
# -----------------------------------------------------------------------------
# A replication is named after its region, as the portal and AVM name them. The
# home region is the registry itself and is not listed here.

resource "azapi_resource" "replications" {
  for_each = var.georeplications

  location  = each.key
  name      = each.key
  parent_id = azapi_resource.this.id
  type      = "Microsoft.ContainerRegistry/registries/replications@2025-11-01"
  body = {
    properties = {
      regionEndpointEnabled = each.value.regional_endpoint_enabled
      zoneRedundancy        = each.value.zone_redundancy_enabled ? "Enabled" : "Disabled"
    }
  }
  tags = each.value.tags
}

# -----------------------------------------------------------------------------
# Image imports
# -----------------------------------------------------------------------------
# Seeds images once, when the key first appears. `NoForce` makes ARM fail the
# import if the target tag already exists, so a re-run against a seeded registry
# would error rather than overwrite: every attribute is therefore ignored after
# creation, and only a replaced registry (an empty one) imports again.

resource "azapi_resource_action" "import_image" {
  for_each = var.import_images

  action      = "importImage"
  method      = "POST"
  resource_id = azapi_resource.this.id
  type        = "Microsoft.ContainerRegistry/registries@2025-11-01"
  body = merge(
    {
      mode = "NoForce"
      source = {
        registryUri = each.value.source_registry_uri
        sourceImage = each.value.source_image
      }
    },
    [for tags in(each.value.target_tags == null ? [] : [each.value.target_tags]) : { targetTags = tags }]...
  )

  lifecycle {
    ignore_changes       = all
    replace_triggered_by = [azapi_resource.this.id]
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
      # A registry emits only resource-specific tables, so there is no destination
      # type to choose: ARM stores null whatever is sent, and any other value here
      # would diff on every plan.
      logAnalyticsDestinationType = null
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
  # Unset optional fields are left out of the body rather than sent as null: ARM
  # returns "" for an unset customNetworkInterfaceName, which would diff against a
  # null. `ignore_null_property` would also cover it, but a change to that flag
  # alone is a PUT, so every endpoint adopted by import would pay a write for it.
  body = {
    properties = merge(
      {
        applicationSecurityGroups = [
          for asg_id in values(each.value.application_security_group_associations) : { id = asg_id }
        ]
        ipConfigurations = [for ip in values(each.value.ip_configurations) : {
          name = ip.name
          properties = merge(
            {
              groupId          = coalesce(ip.subresource_name, each.value.subresource_name)
              privateIPAddress = ip.private_ip_address
            },
            [for member in(ip.member_name == null ? [] : [ip.member_name]) : { memberName = member }]...
          )
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
      },
      [for nic in(each.value.network_interface_name == null ? [] : [each.value.network_interface_name]) : { customNetworkInterfaceName = nic }]...
    )
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

  lifecycle {
    precondition {
      # Same fall-through as the registry-scope assignments above.
      condition     = startswith(local.role_definition_resource_ids[each.value.role_definition_id_or_name], "/")
      error_message = <<-EOT
        A role assignment on private endpoint "${each.value.pe_key}" (map key
        "${each.key}") names the role "${each.value.role_definition_id_or_name}",
        which matched no role definition.

        Pass a role's display name exactly as Azure spells it, or a full
        role-definition resource ID. Names resolve against the roleDefinitions
        catalogue of the provider's subscription, so a CUSTOM role defined in a
        different subscription is not listed there and must be passed as an ID.
      EOT
    }
  }
}
