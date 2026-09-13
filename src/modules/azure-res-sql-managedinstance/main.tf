# =============================================================================
# AZURE SQL MANAGED INSTANCE (Microsoft.Sql/managedInstances)
# =============================================================================
# Mirrors the AVM `Azure/avm-res-sql-managedinstance/azurerm` input surface
# where one exists, and differs from it in the one way that matters most: the
# instance is created by a SINGLE ARM PUT that already carries the identity, the
# key and the SKU.
#
# AVM cannot do that. It builds the instance with `azurerm_mssql_managed_instance`
# and then bolts the rest on with post-create `azapi_resource_action` calls, one
# of which PATCHes the managed identity in AFTER the TDE protector has already
# been ordered. A customer-managed key on a fresh instance therefore always fails
# with `AzureKeyVaultNoServerIdentity`, and the documented workaround is to apply
# once without encryption and again with it - a two-pass apply on a resource that
# takes hours per pass. Here `identity`, `keyId` and `primaryUserAssignedIdentityId`
# go in the create body together, so the ordering problem cannot arise.
#
# ARM splits the rest of the service across child resources, and each one has a
# fixed name it will not accept a substitute for: the Entra admin is
# `ActiveDirectory`, the Entra-only toggle is `Default`, the TDE protector is
# `current`, and the three security children are all `Default`.
#
# FIVE OF THOSE ARE SINGLETONS ARM CREATES ITSELF the moment the instance exists,
# so they are `azapi_update_resource`, not `azapi_resource`. Creating them fails
# a greenfield apply with "Resource already exists" - ARM got there first, with
# rotation off and the scan schedule empty, and the job here is to PATCH them
# into shape. Verified 2026-09-13 against a logical server built by this module
# family that has never configured any of them: all three security children
# answer a GET regardless. The same is true of the instance key: setting `keyId`
# on the instance makes ARM register it, so this module derives the name rather
# than owning it.
#
# ⚠️ ADOPTING AN EXISTING INSTANCE. `azapi_update_resource` has no import
# implementation - `terraform import` answers "Resource Import Not Implemented".
# Import the two `azapi_resource` entries (`this`, `administrator`) and let the
# singletons CREATE: each is a PATCH, so against an already-correct child it
# writes nothing. A post-import plan reading `N to add` is correct, not a sign
# the import was incomplete.
#
# ORDERING. Two dependencies are real but invisible in the graph:
#   1. `azureADOnlyAuthentications` is rejected until an Entra admin exists, so
#      it depends on the administrator child.
#   2. The identity holding wrap/unwrap on the key must already have it. That
#      grant belongs to the caller - this module does not create it, and a first
#      apply against a fresh vault fails with `AzureKeyVaultNoServerIdentity`
#      when it is missing.
#
# NOT COVERED. Managed databases, failover groups, DNS aliases, instance pools
# and the restore/replica create modes (`managedInstanceCreateMode`) are all
# separate ARM surfaces and are not modelled here. Neither are private
# endpoints: a managed instance is injected into a subnet and reachable there,
# so an endpoint would only serve to publish the public data endpoint privately.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # ARM stamps `retentionPolicy` onto every log and metric entry it returns,
  # years after retention moved to the workspace. azapi compares arrays
  # wholesale rather than per-property, so one entry missing it - or one
  # category ARM materialised that the config never sent - makes the whole
  # diagnostic setting diff on every plan, forever.
  diagnostic_retention_policy = { days = 0, enabled = false }

  # The subscription the provider is configured against. Used to list the
  # roleDefinitions catalogue. Built-in roles are present in every subscription,
  # so this resolves any built-in name; a CUSTOM role defined in a different
  # subscription is not in this listing and must be passed as a resource ID.
  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"

  # The input stays a plain resource group name (AVM's shape); the subscription
  # comes from the configured provider, so an aliased or multi-subscription
  # caller still lands in the right place.
  resource_group_resource_id = "${local.provider_subscription_resource_id}/resourceGroups/${var.resource_group_name}"

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

  # vCore counts each SKU offers, from the capabilities API
  # (`Microsoft.Sql/locations/<region>/capabilities`). MEASURED 2026-09-13
  # against northeurope and westeurope, which returned identical lists - the
  # numbers are a property of the hardware family, not the region. What varies
  # by region is whether a family is offered at all, which this cannot see and
  # ARM rejects on its own.
  #
  # Worth catching here because ARM validates the pair late: on a create, the
  # rejection arrives after provisioning has already started.
  supported_vcores = {
    BC_Gen5 = [4, 8, 16, 24, 32, 40, 64, 80]
    GP_Gen5 = [2, 4, 8, 16, 24, 32, 40, 64, 80]
    BC_G8IH = [4, 6, 8, 10, 12, 16, 20, 24, 32, 40, 48, 56, 64, 80, 96, 128]
    BC_G8IM = [4, 6, 8, 10, 12, 16, 20, 24, 32, 40, 48, 56, 64, 80, 96, 128]
    GP_G8IH = [2, 4, 6, 8, 10, 12, 16, 20, 24, 32, 40, 48, 56, 64, 80, 96, 128]
    GP_G8IM = [2, 4, 6, 8, 10, 12, 16, 20, 24, 32, 40, 48, 56, 64, 80, 96, 128]
  }

  # ARM derives nothing here: the instance key's NAME is its identity on the
  # instance, and Azure accepts the vault/key/version triple spelled only this
  # one way. Segments of `https://<vault>.vault.azure.net/keys/<key>/<version>`
  # are 2 (host), 4 (key) and 5 (version); a versionless URI has no segment 5 and
  # drops the third part. The variable's validation guarantees the shape, so the
  # indexing below cannot run off the end.
  customer_managed_key_uri_segments = (
    var.customer_managed_key == null ? [] : split("/", var.customer_managed_key.key_vault_key_uri)
  )

  customer_managed_key_vault_name = (
    var.customer_managed_key == null ? null : split(".", local.customer_managed_key_uri_segments[2])[0]
  )

  instance_key_name = (
    var.customer_managed_key == null ? null :
    length(local.customer_managed_key_uri_segments) > 5
    ? "${local.customer_managed_key_vault_name}_${local.customer_managed_key_uri_segments[4]}_${local.customer_managed_key_uri_segments[5]}"
    : "${local.customer_managed_key_vault_name}_${local.customer_managed_key_uri_segments[4]}"
  )

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
}

# -----------------------------------------------------------------------------
# Managed instance
# -----------------------------------------------------------------------------
# `administrators` is deliberately NOT sent inline. ARM accepts it only at create
# time - "If used for server update, it will be ignored or it will result in an
# error" - so an Entra admin set here would silently stop tracking config on
# every later apply. The `administrators/ActiveDirectory` child below owns it.
#
# `keyId` IS sent whenever `customer_managed_key` is set. It carries no rotation
# flag, so `encryptionProtector` owns `autoRotationEnabled`; the two agree
# because both are handed the same URI. Setting it also makes ARM register the
# instance key, which is why no resource here creates that registration.
#
# What CLEARING it does is not established. `ignore_null_property` drops nulls
# from the request and ARM was measured leaving omitted properties alone, so a
# null `keyId` most likely leaves the protector where it is rather than
# reverting to the service-managed key - but that has not been tested, and it is
# an encryption change on live data if it does. Detach deliberately.
#
# `sku` carries only `name` and `capacity`. ARM derives `tier` and `family` from
# the name and returns all four; an omitted property is not compared, so the two
# derived ones cannot drift. `capacity` and `properties.vCores` are the same
# number by ARM's own definition and are kept in step from one variable.
#
# The admin password goes in `sensitive_body`: ARM never returns it, so a value
# in `body` would diff against an absent response on every plan and print the
# secret in the first one. AzAPI then cannot detect drift in a value it cannot
# read, which is what `sensitive_body_version` is for.

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Sql/managedInstances@2025-01-01"
  body = {
    properties = {
      administratorLogin               = var.administrator_login
      authenticationMetadata           = var.authentication_metadata
      collation                        = var.collation
      databaseFormat                   = var.database_format
      hybridSecondaryUsage             = var.hybrid_secondary_usage
      isGeneralPurposeV2               = var.general_purpose_v2_enabled
      keyId                            = try(var.customer_managed_key.key_vault_key_uri, null)
      licenseType                      = var.license_type
      maintenanceConfigurationId       = var.maintenance_configuration_resource_id
      memorySizeInGB                   = var.memory_size_in_gb
      minimalTlsVersion                = var.minimum_tls_version
      pricingModel                     = var.pricing_model
      primaryUserAssignedIdentityId    = var.primary_user_assigned_identity_resource_id
      proxyOverride                    = var.proxy_override
      publicDataEndpointEnabled        = var.public_data_endpoint_enabled
      requestedBackupStorageRedundancy = var.backup_storage_redundancy
      requestedLogicalAvailabilityZone = var.requested_logical_availability_zone
      storageIOps                      = var.storage_iops
      storageSizeInGB                  = var.storage_size_in_gb
      storageThroughputMBps            = var.storage_throughput_mbps
      subnetId                         = var.subnet_resource_id
      timezoneId                       = var.timezone_id
      vCores                           = var.vcores
      zoneRedundant                    = var.zone_redundant_enabled
    }
    sku = {
      capacity = var.vcores
      name     = var.sku_name
    }
  }

  # Nothing but these two is read. Left unset, azapi stores the WHOLE ARM
  # response in `output`, and a managed instance response carries `state`,
  # `provisioningState` and `currentBackupStorageRedundancy` - values the service
  # moves on its own. Terraform compares the post-apply value against the planned
  # one, so an apply that outlives a transition fails with "Provider produced
  # inconsistent result after apply" and has to be re-run - on a resource whose
  # create is measured in hours.
  response_export_values = {
    dns_zone                    = "properties.dnsZone"
    fully_qualified_domain_name = "properties.fullyQualifiedDomainName"
  }

  tags = var.tags

  # ARM returns resource IDs with a lower-case `resourcegroups` segment in
  # `primaryUserAssignedIdentityId` and in the `userAssignedIdentities` keys,
  # while accepting - and everywhere else returning - `resourceGroups`. That is
  # a spelling difference in an ID, not a change, so comparing case-insensitively
  # avoids an update call that would write the identical value back.
  #
  # This is narrower than it looks and is NOT an ignore_changes: every real
  # difference still plans.
  ignore_casing = true

  # Most of the body above is optional and unset on any given instance. Without
  # this, each of those nulls is compared against whatever ARM returns and
  # renders as a change no apply can settle. With it, nulls are dropped from the
  # request and ARM leaves those properties alone.
  #
  # MEASURED 2026-09-13, migrating both tiers off the AVM module: an apply that
  # sent `authenticationMetadata`, `hybridSecondaryUsage`,
  # `requestedLogicalAvailabilityZone`, `storageIOps`, `storageThroughputMBps`,
  # `administrators` and `sku.family`/`sku.tier` as null left every one of them
  # intact on ARM, and the next plan was clean.
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

  timeouts {
    create = var.timeouts.create
    delete = var.timeouts.delete
    read   = var.timeouts.read
    update = var.timeouts.update
  }

  lifecycle {
    precondition {
      # ARM requires the pair at create time. Without this the apply fails on an
      # ARM error about a missing password rather than on the input that is
      # actually wrong - and on this resource that failure arrives late.
      #
      # Both may be omitted, which is NOT a greenfield path - ARM will not
      # create an instance without a SQL administrator. It is the ADOPT path:
      # an existing Entra-only instance whose create-time password can no longer
      # be produced, and no longer needs to be. `ignore_null_property` drops the
      # null `administratorLogin` from the request, so the login Azure already
      # holds is left alone.
      condition     = var.administrator_login == null || var.administrator_login_password != null
      error_message = "administrator_login_password must be set when administrator_login is. Omit both to adopt an existing instance without managing its SQL administrator."
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

    precondition {
      # Both are rejected by ARM outside next-generation General Purpose, and the
      # rejection arrives after provisioning has started.
      condition     = (var.storage_iops == null && var.storage_throughput_mbps == null) || var.general_purpose_v2_enabled == true
      error_message = "storage_iops and storage_throughput_mbps require general_purpose_v2_enabled = true - ARM rejects provisioned storage performance on any other tier."
    }

    precondition {
      condition     = contains(local.supported_vcores[var.sku_name], var.vcores)
      error_message = "vcores = ${var.vcores} is not offered on ${var.sku_name}. Supported: ${join(", ", [for v in local.supported_vcores[var.sku_name] : tostring(v)])}."
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
  type      = "Microsoft.Sql/managedInstances/administrators@2025-01-01"
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
# Turning it on does not delete the SQL administrator - it only decides whether
# it may connect. Its password also cannot be reset while this is on, which on a
# managed instance makes the create-time credential permanent.

resource "azapi_update_resource" "entra_only_authentication" {
  count = var.entra_only_authentication_enabled != null ? 1 : 0

  name      = "Default"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Sql/managedInstances/azureADOnlyAuthentications@2025-01-01"
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
      error_message = "entra_only_authentication_enabled = true requires entra_administrator - ARM rejects Entra-only authentication on an instance with no Entra admin."
    }
  }
}

# -----------------------------------------------------------------------------
# Customer-managed key
# -----------------------------------------------------------------------------
# The protector names an instance key REGISTRATION rather than a key URI -
# `serverKeyName` is the only handle it takes, and it keeps the `server` spelling
# on a managed instance. That registration is created by ARM when the instance
# body carries `keyId`, so this module derives its name instead of declaring a
# resource that would collide on a greenfield apply.
#
# These two exist alongside the instance's own `keyId`, which is sent as well.
# `keyId` cannot express `auto_rotation_enabled`, so the protector carries it;
# both are handed the same URI, so they agree rather than compete. Terraform
# applies the instance first, so if a bare `keyId` write clears the rotation
# flag, the protector sets it again in the same apply.

resource "azapi_update_resource" "encryption_protector" {
  count = var.customer_managed_key != null ? 1 : 0

  name      = "current"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Sql/managedInstances/encryptionProtector@2025-01-01"
  body = {
    properties = {
      autoRotationEnabled = var.customer_managed_key.auto_rotation_enabled
      serverKeyName       = local.instance_key_name
      serverKeyType       = "AzureKeyVault"
    }
  }
}

# -----------------------------------------------------------------------------
# Threat protection
# -----------------------------------------------------------------------------
# `advancedThreatProtectionSettings` and `securityAlertPolicies` are two ARM
# views of one feature - the newer toggle, and the older resource that also
# carries the notification settings. Both report the same `state`. They are
# exposed separately because the older one is the only way to reach the email
# and suppression lists. Setting them to opposite values is caught by a
# precondition on `security_alert_policy` rather than left to produce an apply
# that writes the state twice.
#
# Both are materialised by ARM with the instance, hence `azapi_update_resource`.

resource "azapi_update_resource" "advanced_threat_protection" {
  count = var.advanced_threat_protection_enabled != null ? 1 : 0

  name      = "Default"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Sql/managedInstances/advancedThreatProtectionSettings@2025-01-01"
  body = {
    properties = {
      state = var.advanced_threat_protection_enabled ? "Enabled" : "Disabled"
    }
  }
}

# Only the properties this module manages are sent. The notification and storage
# fields are omitted rather than nulled when unused: ARM MATERIALISES them as
# `disabledAlerts: [""]`, `emailAddresses: [""]`, `storageEndpoint: ""` and
# `retentionDays: 0`, and a configured null would diff against that forever.
# Omitted properties are not compared at all.

resource "azapi_update_resource" "security_alert_policy" {
  count = var.security_alert_policy != null ? 1 : 0

  name      = "Default"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Sql/managedInstances/securityAlertPolicies@2025-01-01"
  body = {
    properties = merge(
      {
        state = var.security_alert_policy.enabled ? "Enabled" : "Disabled"
      },
      var.security_alert_policy.disabled_alerts == null ? {} : {
        disabledAlerts = var.security_alert_policy.disabled_alerts
      },
      var.security_alert_policy.email_account_admins == null ? {} : {
        emailAccountAdmins = var.security_alert_policy.email_account_admins
      },
      var.security_alert_policy.email_addresses == null ? {} : {
        emailAddresses = var.security_alert_policy.email_addresses
      },
      var.security_alert_policy.retention_in_days == null ? {} : {
        retentionDays = var.security_alert_policy.retention_in_days
      },
      var.security_alert_policy.storage_endpoint == null ? {} : {
        storageEndpoint = var.security_alert_policy.storage_endpoint
      },
    )
  }

  lifecycle {
    precondition {
      # Both resources write the same ARM `state`. Disagreeing values do not
      # error - they produce an apply that sets it twice and settles on whichever
      # Terraform wrote last, then flips again on the next run. Only checkable
      # when both are configured, which is exactly when it can happen.
      condition = (
        var.advanced_threat_protection_enabled == null ||
        var.advanced_threat_protection_enabled == var.security_alert_policy.enabled
      )
      error_message = "security_alert_policy.enabled (${var.security_alert_policy.enabled}) contradicts advanced_threat_protection_enabled (${var.advanced_threat_protection_enabled}). They are two ARM views of one switch - set them alike, or leave advanced_threat_protection_enabled null and let this resource own it."
    }
  }
}

# -----------------------------------------------------------------------------
# Vulnerability assessment
# -----------------------------------------------------------------------------
# Also materialised by ARM with the instance, with scans off. `storageContainerPath`
# is omitted unless supplied: with it, results and baselines go to the caller's
# storage account (the classic configuration); without it, Defender for SQL keeps
# them (the express configuration), and sending an empty string switches nothing
# on while diffing forever.

resource "azapi_update_resource" "vulnerability_assessment" {
  count = var.vulnerability_assessment != null ? 1 : 0

  name      = "Default"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Sql/managedInstances/vulnerabilityAssessments@2025-01-01"
  body = {
    properties = merge(
      {
        recurringScans = merge(
          {
            emailSubscriptionAdmins = var.vulnerability_assessment.email_subscription_admins
            isEnabled               = var.vulnerability_assessment.recurring_scans_enabled
          },
          var.vulnerability_assessment.emails == null ? {} : {
            emails = var.vulnerability_assessment.emails
          },
        )
      },
      var.vulnerability_assessment.storage_container_path == null ? {} : {
        storageContainerPath = var.vulnerability_assessment.storage_container_path
      },
    )
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
