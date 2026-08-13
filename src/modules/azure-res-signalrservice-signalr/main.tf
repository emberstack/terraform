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
#
# ARM keeps `networkACLs` inside the service body, but its per-endpoint rules
# name private endpoints that in turn point back at the service. That cycle is
# why the ACL is written separately, after the endpoints exist — see the block
# further down.
#
# Application security group associations are the opposite case: ARM keeps them
# in the private endpoint body, so they are not a resource of their own.
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
  # SUBNET's subscription — not the service's and not the provider's.
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

  # ARM carries the log toggles twice: as legacy `features` flags ("True"/"False")
  # and as `resourceLogConfiguration` categories ("true"/"false"). It returns both,
  # so both are sent — dropping either would let a full-replace write reset it.
  feature_flags = concat(
    [{ flag = "ServiceMode", properties = {}, value = var.service_mode }],
    [{ flag = "EnableConnectivityLogs", properties = {}, value = var.connectivity_logs_enabled ? "True" : "False" }],
    [{ flag = "EnableMessagingLogs", properties = {}, value = var.messaging_logs_enabled ? "True" : "False" }],
    [{ flag = "EnableLiveTrace", properties = {}, value = try(var.live_trace.enabled, false) ? "True" : "False" }],
  )

  resource_log_categories = [
    { enabled = tostring(var.messaging_logs_enabled), name = "MessagingLogs" },
    { enabled = tostring(var.connectivity_logs_enabled), name = "ConnectivityLogs" },
    { enabled = tostring(var.http_request_logs_enabled), name = "HttpRequestLogs" },
  ]

  # Every role this module assigns across both scopes, as the caller spelled it — a
  # display name or an ARM resource ID. Concatenated rather than merged: the two
  # keyspaces can collide (a service-scope key `a-b` against the `<pe>-<ra>`
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

  # ARM returns request types in this order regardless of how they were sent, so
  # the body is built in the same order to stay diff-stable.
  request_type_order = ["ServerConnection", "ClientConnection", "RESTAPI", "Trace"]

  # ARM names each ACL entry after the private endpoint *connection*
  # ("<service>.<guid>"), not the endpoint resource, and generates that name
  # itself. Map endpoint ID -> connection name from the live service.
  # `terraform import` does not apply `response_export_values`, so the export is
  # absent during an import and the `try` has to tolerate it.
  private_endpoint_connection_names = {
    for connection in try(data.azapi_resource.private_endpoint_connections[0].output.connections, []) :
    lower(connection.private_endpoint_id) => connection.name
  }

  # One entry per ACL rule, with `connection_name = null` standing for "not
  # resolvable yet or at all". Indexing the connection-name map directly inside
  # the body below aborts with Terraform's bare "the given key does not identify
  # an element", which names neither the endpoint nor the cause — and whether the
  # preconditions on `azapi_update_resource.network_acl` get to explain it first
  # depends on what Terraform already knows when it evaluates the body. Resolving
  # to null makes the diagnostic deterministic instead. Null never reaches ARM:
  # a failed precondition fails the plan.
  network_acl_private_endpoint_rules = var.network_acl == null ? {} : {
    for k, v in var.network_acl.private_endpoints : k => {
      allow = [for t in local.request_type_order : t if contains(coalesce(v.allowed_request_types, []), t)]
      deny  = [for t in local.request_type_order : t if contains(coalesce(v.denied_request_types, []), t)]
      connection_name = try(
        local.private_endpoint_connection_names[lower(azapi_resource.private_endpoint[k].id)],
        null
      )
    }
  }
}

# -----------------------------------------------------------------------------
# SignalR service
# -----------------------------------------------------------------------------

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.SignalRService/signalR@2024-03-01"
  body = {
    properties = {
      cors = var.cors_allowed_origins == null ? null : {
        allowedOrigins = var.cors_allowed_origins
      }
      disableAadAuth   = !var.aad_auth_enabled
      disableLocalAuth = !var.local_auth_enabled
      features         = local.feature_flags
      liveTraceConfiguration = var.live_trace == null ? null : {
        categories = [
          { enabled = tostring(var.live_trace.messaging_logs_enabled), name = "MessagingLogs" },
          { enabled = tostring(var.live_trace.connectivity_logs_enabled), name = "ConnectivityLogs" },
          { enabled = tostring(var.live_trace.http_request_logs_enabled), name = "HttpRequestLogs" },
        ]
        enabled = tostring(var.live_trace.enabled)
      }
      publicNetworkAccess      = var.public_network_access_enabled ? "Enabled" : "Disabled"
      resourceLogConfiguration = { categories = local.resource_log_categories }
      serverless = {
        connectionTimeoutInSeconds = var.serverless_connection_timeout_in_seconds
      }
      tls = {
        clientCertEnabled = var.tls_client_cert_enabled
      }
      upstream = {
        templates = [for endpoint in var.upstream_endpoints : {
          # `resource` is the audience the issued token is minted for (the `aud`
          # claim), not an identity resource ID.
          auth = endpoint.managed_identity_audience == null ? null : {
            managedIdentity = { resource = endpoint.managed_identity_audience }
            type            = "ManagedIdentity"
          }
          categoryPattern = endpoint.category_pattern
          eventPattern    = endpoint.event_pattern
          hubPattern      = endpoint.hub_pattern
          urlTemplate     = endpoint.url_template
        }]
      }
    }
    sku = {
      capacity = var.sku_capacity
      name     = var.sku_name
    }
  }
  # `cors` and `liveTraceConfiguration` are null when the caller does not set them,
  # but ARM populates both, which would diff forever without this.
  ignore_null_property = true
  response_export_values = {
    host_name   = "properties.hostName"
    public_port = "properties.publicPort"
    server_port = "properties.serverPort"
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
    # `networkACLs` is written by azapi_update_resource below. An import pulls the
    # live value into this body, and without this the next write would drop it —
    # resetting the service to its default-allow posture.
    ignore_changes = [body.properties.networkACLs]
  }
}

# -----------------------------------------------------------------------------
# Network ACL
# -----------------------------------------------------------------------------
# Each rule is keyed by the server-generated connection name ("<service>.<guid>",
# unrelated to the endpoint's own resourceGuid), so the service has to be re-read
# to learn them.
#
# Deliberately NO `depends_on` here. With one, Terraform defers this read to apply
# time whenever the service has any pending change, which leaves `name` unknown
# inside a list — and azapi cannot plan an unknown inside a body list ("tuple
# required", provider bug). Reading at plan time keeps the name concrete.
#
# The cost is the very first apply of a brand-new service: the connection does not
# exist yet, so the lookup below fails and the apply must be run once more. Every
# later apply is clean.

data "azapi_resource" "private_endpoint_connections" {
  count = var.network_acl != null && length(var.private_endpoints) > 0 ? 1 : 0

  resource_id = azapi_resource.this.id
  type        = "Microsoft.SignalRService/signalR@2024-03-01"
  response_export_values = {
    connections = "properties.privateEndpointConnections[].{name: name, private_endpoint_id: properties.privateEndpoint.id}"
  }
}

resource "azapi_update_resource" "network_acl" {
  count = var.network_acl != null ? 1 : 0

  resource_id = azapi_resource.this.id
  type        = "Microsoft.SignalRService/signalR@2024-03-01"
  body = {
    properties = {
      # `publicNetwork` is omitted rather than sent as null when unset. ARM always
      # materialises the property — a service that has never been given one reports
      # every request type allowed — so a null would diff on every plan, and
      # `azapi_update_resource` has no `ignore_null_property` to suppress it.
      # Omitting leaves whatever ARM holds, which for an unset service is
      # permissive: pair `default_action = "Deny"` with an explicit
      # `public_network` to actually close public access.
      networkACLs = merge(
        {
          defaultAction = var.network_acl.default_action
          privateEndpoints = [
            for k, rule in local.network_acl_private_endpoint_rules : {
              allow = rule.allow
              deny  = rule.deny
              name  = rule.connection_name
            }
          ]
        },
        var.network_acl.public_network == null ? {} : {
          publicNetwork = {
            allow = [for t in local.request_type_order : t if contains(coalesce(var.network_acl.public_network.allowed_request_types, []), t)]
            deny  = [for t in local.request_type_order : t if contains(coalesce(var.network_acl.public_network.denied_request_types, []), t)]
          }
        }
      )
    }
  }
  lifecycle {
    precondition {
      condition = alltrue([
        for k in keys(var.network_acl.private_endpoints) : contains(keys(var.private_endpoints), k)
      ])
      error_message = "Every key in network_acl.private_endpoints must also exist in private_endpoints."
    }
    precondition {
      # Skips keys the precondition above already rejects, so a typo'd key
      # reports the one error that explains it rather than two.
      condition = alltrue([
        for k, rule in local.network_acl_private_endpoint_rules :
        rule.connection_name != null if contains(keys(var.private_endpoints), k)
      ])
      error_message = <<-EOT
        An ACL rule in network_acl.private_endpoints names a private endpoint whose
        connection the SignalR service does not report yet.

        On the first apply of a brand-new service this is expected: the connection
        does not exist until the endpoint has been created, so run apply once more.
        Every later apply is clean.

        Otherwise the endpoint's connection is missing or in a non-approved state —
        check properties.privateEndpointConnections on the service.
      EOT
    }
  }
}

# -----------------------------------------------------------------------------
# Access keys
# -----------------------------------------------------------------------------
# Reading keys costs an extra listKeys call and a wider permission requirement,
# so it is opt-in. With `local_auth_enabled = false` the keys are inert anyway.

resource "azapi_resource_action" "access_keys" {
  count = var.include_access_keys ? 1 : 0

  action      = "listKeys"
  method      = "POST"
  resource_id = azapi_resource.this.id
  type        = "Microsoft.SignalRService/signalR@2024-03-01"

  # Named rather than ["*"] so state holds only the four values that are actually
  # published, and `outputs.tf` reads module-cased names instead of raw ARM ones.
  # listKeys returns nothing else today, but ["*"] would carry anything ARM adds
  # into state without review — on the one output in this module that is secret.
  response_export_values = {
    primary_connection_string   = "primaryConnectionString"
    primary_key                 = "primaryKey"
    secondary_connection_string = "secondaryConnectionString"
    secondary_key               = "secondaryKey"
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

  lifecycle {
    precondition {
      # Same fall-through as the service-scope assignments above.
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
