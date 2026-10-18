# =============================================================================
# ENTRA DOMAIN SERVICES (Microsoft.AAD/domainServices)
# =============================================================================
# A Microsoft Entra Domain Services managed domain. There is no Terraform AVM
# module for this resource — `avm-res-aad-domainservice` is still a proposal —
# so the shape follows the Bicep `avm/res/aad/domain-service` module, with the
# initial replica set split out of `replica_sets` and the security knobs named
# the way the azurerm provider names them.
#
# Changing `name`, `location` or `resource_group_name` replaces the resource,
# and deleting a managed domain deletes everything in it: OUs, group policy,
# computer accounts and every synchronised password hash. Users must change
# their passwords again before they can sign in to a replacement. Put a lock on
# it.
#
# `domain_name`, the initial replica set's subnet and
# `domain_configuration_type` cannot change after create either. azurerm
# forces a replacement for them; this module deliberately does not, so a change
# reaches ARM as an update, where it is expected to be rejected — a failed apply
# is the better outcome than a planned deletion.
#
# Forest trusts (`resourceForestSettings`) are never sent. Whether ARM keeps
# trusts created elsewhere across a PUT that omits them is untested, so a domain
# with trusts must not be managed here.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The subscription the provider is configured against. Used to list the
  # roleDefinitions catalogue and the region catalogue. Built-in roles are
  # present in every subscription, so this resolves any built-in name; a CUSTOM
  # role defined in a different subscription is not in this listing and must be
  # passed as a resource ID.
  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  resource_group_resource_id        = "${local.provider_subscription_resource_id}/resourceGroups/${var.resource_group_name}"

  # The initial replica set lives in the resource's own region and goes first —
  # the azurerm provider likewise treats the first entry ARM returns as the
  # initial one. Replica set entries carry no `name`, so azapi pairs the sent and
  # returned lists by position: additional replica sets are appended, never
  # inserted, or every entry after the insertion diffs.
  replica_sets = concat(
    [{ location = var.location, subnet_resource_id = var.subnet_resource_id }],
    var.replica_sets,
  )

  # Region display names keyed lower-case with spaces removed, the same fold
  # applied to each replica set's region, so `westeurope` and `West Europe` both
  # find `West Europe`. ARM returns a replica
  # set's region as its display name whatever was sent, and azapi compares
  # nested strings literally — sending `westeurope` diffs every replica set on
  # every plan. The resource's top-level `location` is normalised by azapi
  # itself and keeps the input.
  region_display_names = {
    for region in data.azapi_resource_action.locations.output.locations :
    lower(replace(region.name, " ", "")) => region.display_name
  }
  replica_set_display_locations = [
    for replica_set in local.replica_sets :
    lookup(local.region_display_names, lower(replace(replica_set.location, " ", "")), null)
  ]

  # Each replica set joined to what ARM reports for it, for the outputs. Matched
  # by subnet ID rather than by region: a subnet holds at most one replica set,
  # and its ID survives whatever spelling of the region ARM returns. `try`
  # because an import does not apply `response_export_values`.
  replica_set_outputs = [
    for replica_set in local.replica_sets : merge(replica_set, {
      arm = try(one([
        for reported in azapi_resource.this.output.replica_sets : reported
        if lower(reported.subnet_id) == lower(replica_set.subnet_resource_id)
      ]), null)
    })
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
# Managed domain
# -----------------------------------------------------------------------------
# Every security setting is sent, whether or not the caller changed it. The REST
# defaults are the permissive ones — NTLMv1, TLS 1.0 and RC4 all `Enabled` — and
# a full-replace write resets anything it leaves out.
#
# The secure LDAP certificate travels in `body`, on every write, the way the
# azurerm provider sends it. `sensitive_body` would keep it out of state, but it
# is version-gated: an unchanged version OMITS the path from the request, and
# whether ARM keeps the installed certificate across a PUT that enables LDAPS
# without one is untested. ARM never returns the PFX or its password, and
# `ignore_missing_property` (the provider default) keeps their absence from the
# response from diffing.
#
# ARM reports the create as finished before the domain controllers are online.
# Microsoft documents up to an hour more of background provisioning, and the
# azurerm provider polls until every replica set reports two controllers. AzAPI
# cannot wait on response content, so `domain_controller_ip_addresses` can be
# empty after the first apply and fills in on a later refresh.

resource "azapi_resource" "this" {
  location  = var.location
  name      = coalesce(var.name, var.domain_name)
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.AAD/domainServices@2025-06-01"
  body = {
    properties = {
      domainConfigurationType = var.domain_configuration_type
      domainName              = var.domain_name
      domainSecuritySettings = {
        channelBinding           = var.security.channel_binding_enabled ? "Enabled" : "Disabled"
        kerberosArmoring         = var.security.kerberos_armoring_enabled ? "Enabled" : "Disabled"
        kerberosRc4Encryption    = var.security.kerberos_rc4_encryption_enabled ? "Enabled" : "Disabled"
        ldapSigning              = var.security.ldap_signing_enabled ? "Enabled" : "Disabled"
        ntlmV1                   = var.security.ntlm_v1_enabled ? "Enabled" : "Disabled"
        syncKerberosPasswords    = var.security.sync_kerberos_passwords ? "Enabled" : "Disabled"
        syncNtlmPasswords        = var.security.sync_ntlm_passwords ? "Enabled" : "Disabled"
        syncOnPremPasswords      = var.security.sync_on_prem_passwords ? "Enabled" : "Disabled"
        syncOnPremSamAccountName = var.security.sync_on_prem_sam_account_name ? "Enabled" : "Disabled"
        # The service no longer accepts TLS 1.0 or 1.1 — the ability to turn
        # TLS 1.2-only mode off has been removed — so there is no choice to expose.
        tlsV1 = "Disabled"
      }
      filteredSync = var.filtered_sync_enabled ? "Enabled" : "Disabled"
      ldapsSettings = {
        externalAccess         = try(var.secure_ldap.external_access_enabled, false) ? "Enabled" : "Disabled"
        ldaps                  = var.secure_ldap == null ? "Disabled" : "Enabled"
        pfxCertificate         = try(var.secure_ldap_certificate.pfx_certificate, null)
        pfxCertificatePassword = try(var.secure_ldap_certificate.pfx_certificate_password, null)
      }
      notificationSettings = {
        additionalRecipients = var.notifications.additional_recipients
        notifyDcAdmins       = var.notifications.notify_dc_admins ? "Enabled" : "Disabled"
        notifyGlobalAdmins   = var.notifications.notify_global_admins ? "Enabled" : "Disabled"
      }
      replicaSets = [
        for index, replica_set in local.replica_sets : {
          location = local.replica_set_display_locations[index]
          subnetId = replica_set.subnet_resource_id
        }
      ]
      sku       = var.sku
      syncScope = var.sync_scope
    }
  }

  # The certificate and its password are null while secure LDAP is off. Dropping
  # the nulls keeps them out of the request rather than sending an explicit
  # "clear this".
  ignore_null_property = true

  # Nothing but these is read. Left unset, azapi stores the WHOLE ARM response in
  # `output`, and each replica set carries `serviceStatus`, `healthMonitors`,
  # `healthAlerts` and `healthLastEvaluated` — values the service moves on its
  # own. Terraform compares the post-apply value against the planned one, so an
  # apply that outlives a health evaluation fails with "Provider produced
  # inconsistent result after apply".
  response_export_values = {
    certificate_not_after  = "properties.ldapsSettings.certificateNotAfter"
    certificate_thumbprint = "properties.ldapsSettings.certificateThumbprint"
    deployment_id          = "properties.deploymentId"
    replica_sets           = "properties.replicaSets[].{replica_set_id: replicaSetId, subnet_id: subnetId, domain_controller_ip_addresses: domainControllerIpAddress, external_access_ip_address: externalAccessIpAddress}"
  }

  tags = var.tags

  timeouts {
    create = var.timeouts.create
    delete = var.timeouts.delete
    read   = var.timeouts.read
    update = var.timeouts.update
  }

  lifecycle {
    precondition {
      # A region missing from the catalogue would otherwise reach ARM as null,
      # which `ignore_null_property` drops from the request.
      condition     = alltrue([for location in local.replica_set_display_locations : location != null])
      error_message = <<-EOT
        A replica set region is not in the subscription's region catalogue:
        ${join(", ", [for index, replica_set in local.replica_sets : replica_set.location if local.replica_set_display_locations[index] == null])}.

        Pass `location` and each `replica_sets` location as an Azure region name
        (`westeurope`) or display name (`West Europe`).
      EOT
    }
  }
}

# The subscription's region catalogue, read on every plan to translate replica
# set regions into the display names ARM echoes back.
data "azapi_resource_action" "locations" {
  action      = "locations"
  method      = "GET"
  resource_id = local.provider_subscription_resource_id
  type        = "Microsoft.Resources/subscriptions@2022-12-01"
  response_export_values = {
    locations = "value[].{name: name, display_name: displayName}"
  }
}

# -----------------------------------------------------------------------------
# Lock
# -----------------------------------------------------------------------------

resource "azapi_resource" "lock" {
  count = var.lock != null ? 1 : 0

  name      = coalesce(var.lock.name, "lock-${azapi_resource.this.name}")
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
