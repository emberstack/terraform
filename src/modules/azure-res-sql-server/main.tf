# =============================================================================
# AZURE SQL LOGICAL SERVER (Microsoft.Sql/servers)
# =============================================================================
# Mirrors the AVM `Azure/avm-res-sql-server/azurerm` input surface where one
# exists, and covers what that module does not:
#   - TDE auto-rotation (AVM sets `keyId` inline, which pins a key version)
#   - server auditing (AVM declares no auditing resource at all)
#   - the Entra administrator as a child resource, so it survives updates
#
# ARM splits this service across several child resources, and each one has a
# fixed name it will not accept a substitute for: the Entra admin is
# `ActiveDirectory`, the Entra-only toggle is `Default`, the TDE protector is
# `current`, and auditing is `default`.
#
# THREE OF THOSE ARE SINGLETONS ARM CREATES ITSELF the moment the server exists,
# so they are `azapi_update_resource`, not `azapi_resource`. Creating them fails
# a greenfield apply with "Resource already exists" - ARM got there first, with
# auditing disabled and rotation off, and the job here is to PATCH them into
# shape. The same is true of the server key: setting `keyId` on the server makes
# ARM register it, so this module derives the name rather than owning it.
#
# ORDERING. Two dependencies are real but invisible in the graph:
#   1. `azureADOnlyAuthentications` is rejected until an Entra admin exists, so
#      it depends on the administrator child.
#   2. The identity holding wrap/unwrap on the key must already have it. That
#      grant belongs to the caller - this module does not create it, and a first
#      apply against a fresh vault fails with `AzureKeyVaultNoServerIdentity`
#      when it is missing.
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
  # SUBNET's subscription - not the server's and not the provider's.
  private_endpoint_subscription_resource_ids = {
    for k, v in var.private_endpoints : k => join("/", slice(split("/", v.subnet_resource_id), 0, 3))
  }

  # `sensitive_body_version` IS persisted to state, so it cannot be gated on the
  # ephemeral password variable - Terraform rejects an ephemeral value in a
  # non-write-only attribute. `administrator_login` is the non-ephemeral half of
  # the same pair, so it gates both halves and they stay in step.
  manage_administrator_password = var.administrator_login != null

  has_user_assigned   = length(var.managed_identities.user_assigned_resource_ids) > 0
  has_system_assigned = var.managed_identities.system_assigned
  identity_type = (
    local.has_system_assigned && local.has_user_assigned ? "SystemAssigned, UserAssigned" :
    local.has_system_assigned ? "SystemAssigned" :
    local.has_user_assigned ? "UserAssigned" :
    null
  )

  # ARM derives nothing here: the server key's NAME is its identity on the
  # server, and Azure accepts the vault/key/version triple spelled only this one
  # way. Segments of `https://<vault>.vault.azure.net/keys/<key>/<version>` are 2
  # (host), 4 (key) and 5 (version); a versionless URI has no segment 5 and drops
  # the third part. The variable's validation guarantees the shape, so the
  # indexing below cannot run off the end.
  customer_managed_key_uri_segments = (
    var.customer_managed_key == null ? [] : split("/", var.customer_managed_key.key_vault_key_uri)
  )

  customer_managed_key_vault_name = (
    var.customer_managed_key == null ? null : split(".", local.customer_managed_key_uri_segments[2])[0]
  )

  server_key_name = (
    var.customer_managed_key == null ? null :
    length(local.customer_managed_key_uri_segments) > 5
    ? "${local.customer_managed_key_vault_name}_${local.customer_managed_key_uri_segments[4]}_${local.customer_managed_key_uri_segments[5]}"
    : "${local.customer_managed_key_vault_name}_${local.customer_managed_key_uri_segments[4]}"
  )

  # Every role this module assigns across both scopes, as the caller spelled it - a
  # display name or an ARM resource ID. Concatenated rather than merged: the two
  # keyspaces can collide (a server-scope key `a-b` against the `<pe>-<ra>`
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
}

# -----------------------------------------------------------------------------
# Server
# -----------------------------------------------------------------------------
# `administrators` is deliberately NOT sent inline. ARM accepts it only at create
# time - "If used for server update, it will be ignored or it will result in an
# error" - so an Entra admin set here would silently stop tracking config on
# every later apply. The `administrators/ActiveDirectory` child below owns it.
#
# `keyId` IS sent. It is a real server property that ARM echoes back, and an
# azapi update is a full replace - omitting it would strip the TDE protector
# down to the service-managed key. It carries no rotation flag, so
# `encryptionProtector` still owns `autoRotationEnabled`; the two agree because
# both are handed the same URI. Setting it also makes ARM register the server
# key, which is why no resource here creates that registration.
#
# The admin password goes in `sensitive_body`: ARM never returns it, so a value
# in `body` would diff against an absent response on every plan and print the
# secret in the first one. AzAPI then cannot detect drift in a value it cannot
# read, which is what `sensitive_body_version` is for.

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Sql/servers@2025-01-01"
  body = {
    properties = {
      administratorLogin            = var.administrator_login
      federatedClientId             = var.federated_client_id
      keyId                         = try(var.customer_managed_key.key_vault_key_uri, null)
      minimalTlsVersion             = var.minimum_tls_version
      primaryUserAssignedIdentityId = var.primary_user_assigned_identity_resource_id
      publicNetworkAccess           = var.public_network_access_enabled ? "Enabled" : "Disabled"
      restrictOutboundNetworkAccess = var.outbound_network_restriction_enabled ? "Enabled" : "Disabled"
      version                       = var.server_version
    }
  }
  response_export_values = { fully_qualified_domain_name = "properties.fullyQualifiedDomainName" }
  tags                   = var.tags

  # ARM returns resource IDs with a lower-case `resourcegroups` segment here
  # while accepting - and everywhere else returning - `resourceGroups`. That is
  # a spelling difference in an ID, not a change, so comparing case-insensitively
  # avoids an update call that would write the identical value back.
  #
  # This is narrower than it looks and is NOT an ignore_changes: every real
  # difference still plans. `administrators` needs no such treatment - ARM
  # documents it as ignored on update, and the body it echoes after an import is
  # replaced by the configured body on the first apply.
  ignore_casing = true

  # A server created without `administrator_login` still gets an Azure-generated
  # `CloudSA…` one, and ARM will not accept a null to clear it. Comparing that
  # against the configured null is a diff no apply can settle.
  ignore_null_property = true

  sensitive_body = local.manage_administrator_password ? {
    properties = {
      administratorLoginPassword = var.administrator_login_password
    }
  } : {}

  sensitive_body_version = local.manage_administrator_password ? {
    "properties.administratorLoginPassword" = var.administrator_login_password_version
  } : {}

  dynamic "identity" {
    for_each = local.identity_type == null ? [] : [local.identity_type]
    content {
      type         = identity.value
      identity_ids = var.managed_identities.user_assigned_resource_ids
    }
  }

  lifecycle {
    precondition {
      # ARM requires the pair at create time. Without this the apply fails on an
      # ARM error about a missing password rather than on the input that is
      # actually wrong.
      condition     = var.administrator_login == null || var.administrator_login_password != null
      error_message = "administrator_login_password must be set when administrator_login is. Omit both to let Azure generate the provisioning-only CloudSA account, which cannot connect."
    }

    precondition {
      # TDE resolves the key THROUGH the primary user-assigned identity. Without
      # one, a create carrying `keyId` fails inside ARM with
      # `AzureKeyVaultNoServerIdentity`, which names neither input.
      condition     = var.customer_managed_key == null || var.primary_user_assigned_identity_resource_id != null
      error_message = "customer_managed_key requires primary_user_assigned_identity_resource_id - TDE resolves the key through that identity."
    }

    precondition {
      # A primary identity that is not also attached is accepted by Terraform and
      # rejected by ARM. Compared case-insensitively because ARM round-trips the
      # `resourceGroups` segment in lower case.
      condition = var.primary_user_assigned_identity_resource_id == null || contains(
        [for id in var.managed_identities.user_assigned_resource_ids : lower(id)],
        lower(coalesce(var.primary_user_assigned_identity_resource_id, "unset"))
      )
      error_message = "primary_user_assigned_identity_resource_id must also appear in managed_identities.user_assigned_resource_ids."
    }
  }
}

# -----------------------------------------------------------------------------
# Entra administrator
# -----------------------------------------------------------------------------
# ARM fixes the name at `ActiveDirectory` and `administratorType` at
# `ActiveDirectory`; neither is a choice. `sid` is the object ID of the user or
# group, and `login` is only a display label - Azure does not resolve it, so a
# wrong value there is cosmetic rather than an authentication failure.

resource "azapi_resource" "administrator" {
  count = var.entra_administrator != null ? 1 : 0

  name      = "ActiveDirectory"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Sql/servers/administrators@2025-01-01"
  body = {
    properties = {
      administratorType = "ActiveDirectory"
      login             = var.entra_administrator.login
      sid               = var.entra_administrator.object_id
      tenantId          = coalesce(var.entra_administrator.tenant_id, data.azapi_client_config.current.tenant_id)
    }
  }
}

# -----------------------------------------------------------------------------
# Entra-only authentication
# -----------------------------------------------------------------------------
# ARM rejects enabling this before an Entra admin exists, and the admin above is
# a sibling rather than a parent, so the ordering needs stating explicitly.
#
# Turning it on does not delete existing SQL logins - it only decides whether
# they may connect. The SQL admin password also cannot be reset while it is on.

resource "azapi_update_resource" "entra_only_authentication" {
  count = var.entra_only_authentication_enabled != null ? 1 : 0

  name      = "Default"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Sql/servers/azureADOnlyAuthentications@2025-01-01"
  body = {
    properties = {
      azureADOnlyAuthentication = var.entra_only_authentication_enabled
    }
  }

  depends_on = [azapi_resource.administrator]

  lifecycle {
    precondition {
      # `depends_on` orders these two but cannot conjure an admin that was never
      # configured. ARM refuses to enable the toggle without one, so catch it
      # here rather than mid-apply.
      condition     = var.entra_only_authentication_enabled != true || var.entra_administrator != null
      error_message = "entra_only_authentication_enabled = true requires entra_administrator - ARM rejects Entra-only authentication on a server with no Entra admin."
    }
  }
}

# -----------------------------------------------------------------------------
# Connection policy
# -----------------------------------------------------------------------------
# A child resource rather than a server property, which is why it survives a
# server body replace untouched. Null leaves it unmanaged on Azure's default.
#
# ARM materialises this the moment the server exists, so it is PATCHed rather
# than created - see the singleton note in the banner.

resource "azapi_update_resource" "connection_policy" {
  count = var.connection_policy != null ? 1 : 0

  name      = "default"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Sql/servers/connectionPolicies@2025-01-01"
  body = {
    properties = {
      connectionType = var.connection_policy
    }
  }
}

# -----------------------------------------------------------------------------
# Customer-managed key
# -----------------------------------------------------------------------------
# The protector names a server key REGISTRATION rather than a key URI -
# `serverKeyName` is the only handle it takes. That registration is created by
# ARM when the server body carries `keyId`, so this module derives its name
# instead of declaring a resource that would collide on a greenfield apply.
#
# These two exist alongside the server's own `keyId`, which is sent as well.
# `keyId` cannot express `auto_rotation_enabled`, so the protector carries it;
# both are handed the same URI, so they agree rather than compete. Terraform
# applies the server first, so if a bare `keyId` write clears the rotation flag,
# the protector sets it again in the same apply.
#
# With rotation on, the server polls the vault and moves the protector to a new
# key version within 24 hours; with it off, the version in the URI is where the
# protector stays.


resource "azapi_update_resource" "encryption_protector" {
  count = var.customer_managed_key != null ? 1 : 0

  name      = "current"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Sql/servers/encryptionProtector@2025-01-01"
  body = {
    properties = {
      autoRotationEnabled = var.customer_managed_key.auto_rotation_enabled
      serverKeyName       = local.server_key_name
      serverKeyType       = "AzureKeyVault"
    }
  }
}

# -----------------------------------------------------------------------------
# Auditing
# -----------------------------------------------------------------------------
# Server-level auditing. `isAzureMonitorTargetEnabled` only routes the events -
# they land nowhere until a diagnostic setting carrying the
# `SQLSecurityAuditEvents` category exists on the server's `master` DATABASE.
# That setting belongs to the caller; `diagnostic_settings` on this module
# targets the server, which is a different scope.

resource "azapi_update_resource" "auditing" {
  count = var.auditing != null ? 1 : 0

  name      = "default"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Sql/servers/auditingSettings@2025-01-01"

  # Only the properties this module manages are sent. The blob-auditing fields
  # are omitted rather than nulled when unused: ARM MATERIALISES them as
  # `retentionDays: 0` and `storageEndpoint: ""`, and a configured null would
  # diff against that forever. Omitted properties are not compared at all.
  body = {
    properties = merge(
      {
        auditActionsAndGroups       = var.auditing.audit_actions_and_groups
        isAzureMonitorTargetEnabled = var.auditing.log_monitoring_enabled
        state                       = var.auditing.enabled ? "Enabled" : "Disabled"
      },
      var.auditing.storage_endpoint == null ? {} : { storageEndpoint = var.auditing.storage_endpoint },
      var.auditing.retention_in_days == null ? {} : { retentionDays = var.auditing.retention_in_days },
      var.auditing.storage_account_secondary_key_in_use == null ? {} : {
        isStorageSecondaryKeyInUse = var.auditing.storage_account_secondary_key_in_use
      },
    )
  }
}

# -----------------------------------------------------------------------------
# Firewall and virtual network rules
# -----------------------------------------------------------------------------
# A firewall rule with both addresses set to 0.0.0.0 is the "Allow Azure services
# and resources to access this server" switch rather than a literal range. It is
# left to the caller to express, because it is a real exception to a private
# server and should read as one at the call site.

resource "azapi_resource" "firewall_rules" {
  for_each = var.firewall_rules

  name      = coalesce(each.value.name, each.key)
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Sql/servers/firewallRules@2025-01-01"
  body = {
    properties = {
      endIpAddress   = each.value.end_ip_address
      startIpAddress = each.value.start_ip_address
    }
  }
}

resource "azapi_resource" "virtual_network_rules" {
  for_each = var.virtual_network_rules

  name      = coalesce(each.value.name, each.key)
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Sql/servers/virtualNetworkRules@2025-01-01"
  body = {
    properties = {
      ignoreMissingVnetServiceEndpoint = each.value.ignore_missing_vnet_service_endpoint
      virtualNetworkSubnetId           = each.value.subnet_resource_id
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
# `applicationSecurityGroups` live in the private endpoint body - ARM has no
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

  lifecycle {
    precondition {
      # Same fall-through as the server-scope assignments above.
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
