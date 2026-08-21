# =============================================================================
# CLUSTER EXTENSION (Microsoft.KubernetesConfiguration/extensions)
# =============================================================================
# A ProxyResource on a cluster: `parent_id` is the cluster's own resource ID, so
# any cluster RP the extensions RP accepts works, and there is no location and no
# tags to set. `diagnostic_settings` is absent for the same kind of reason — the
# type publishes no log or metric categories. Resource-scoped `role_assignments`
# are left out deliberately: rights over an extension instance are not something
# callers grant, rights FOR its identity are, and those are
# `identity_role_assignments`.
#
# `Extensions_Update` (PATCH) accepts exactly six properties —
# autoUpgradeMinorVersion, autoUpgradeMode, releaseTrain, version,
# configurationSettings, configurationProtectedSettings. Everything else is
# create-only, and AzAPI writes with PUT, so the immutable set is listed in
# `replace_triggers_external_values` rather than left to drift silently.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The subscription the provider is configured against. Used to list the
  # roleDefinitions catalogue. Built-in roles are present in every subscription,
  # so this resolves any built-in name; a CUSTOM role defined in a different
  # subscription is not in this listing and must be passed as a resource ID.
  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"

  # ARM models the two scopes as mutually exclusive children of one object and
  # spells the namespace differently in each, so a single input field lands under
  # the right key and a body naming both children cannot be expressed.
  #
  # Terraform unifies the two branches to `map(map(string))`. Checked: the losing
  # branch's key is NOT merged in, and a null namespace survives as null. Both
  # leaves are strings, so nothing is lost — add a non-string field to either and
  # it is silently stringified.
  scope_body = var.scope.kind == "cluster" ? {
    cluster = {
      releaseNamespace = var.scope.namespace
    }
    } : {
    namespace = {
      targetNamespace = var.scope.namespace
    }
  }

  # An extension's identity arrives by one of two routes: on AKS the resource
  # provider assigns one and reports it under `properties.aksAssignedIdentity`,
  # whether or not `identity` was requested; elsewhere it is the resource's own
  # system-assigned identity. Both are computed, so this stays unknown until
  # apply — which is what the role assignments below need it to be.
  aks_assigned_principal_id    = try(azapi_resource.this.output.aks_assigned_identity_principal_id, null)
  system_assigned_principal_id = try(azapi_resource.this.identity[0].principal_id, null)
  extension_principal_id       = local.aks_assigned_principal_id != null ? local.aks_assigned_principal_id : local.system_assigned_principal_id

  # Every role this module assigns, as the caller spelled it — a display name or an
  # ARM resource ID. Deduplication happens in `role_definition_resource_ids`.
  role_definition_names = [for v in values(var.identity_role_assignments) : v.role_definition_id_or_name]

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
# Extension
# -----------------------------------------------------------------------------
# `configurationProtectedSettings` goes in `sensitive_body`, not `body`: ARM never
# returns it, so a value in `body` would diff against an absent response on every
# plan and print the secret in the first one. AzAPI then cannot detect drift in a
# value it cannot read, which is what `sensitive_body_version` is for.

resource "azapi_resource" "this" {
  name      = var.name
  parent_id = var.cluster_resource_id
  type      = "Microsoft.KubernetesConfiguration/extensions@2025-03-01"
  body = {
    plan = var.plan == null ? null : {
      name          = var.plan.name
      product       = var.plan.product
      promotionCode = var.plan.promotion_code
      publisher     = var.plan.publisher
      version       = var.plan.version
    }
    properties = {
      autoUpgradeMinorVersion = var.auto_upgrade_minor_version
      autoUpgradeMode         = var.auto_upgrade_mode
      configurationSettings   = var.configuration_settings
      extensionType           = var.extension_type
      # ARM honours one at a time — `releaseTrain` only while auto-upgrade is on,
      # `version` only while it is off. The inapplicable one is sent as null rather
      # than as a value ARM silently drops, so the response can never disagree with
      # the config about which mode is in force.
      releaseTrain = var.auto_upgrade_minor_version ? var.release_train : null
      scope        = local.scope_body
      version      = var.auto_upgrade_minor_version ? null : var.extension_version
    }
  }

  # ARM's default delete waits on the in-cluster uninstall and never finishes when
  # the release is wedged. Read the warning on the variable before enabling this.
  delete_query_parameters = var.force_delete ? { forceDelete = ["true"] } : {}

  # The resource provider materialises defaults for properties this module can send
  # as null — a `releaseNamespace` chosen for the extension type,
  # `releaseTrain: "Stable"` — and returns them on the next read. Each would
  # otherwise be a permanent diff against the null that was sent.
  ignore_null_property = true

  # The create-only set, per the banner. A PUT changing any of these is not a
  # re-install: the instance keeps running the old chart while state claims
  # otherwise, so replacing is the only honest read of the change.
  replace_triggers_external_values = [
    var.cluster_resource_id,
    var.extension_type,
    var.managed_identities,
    var.plan,
    var.scope,
  ]

  response_export_values = {
    aks_assigned_identity_principal_id = "properties.aksAssignedIdentity.principalId"
    current_version                    = "properties.currentVersion"
    provisioning_state                 = "properties.provisioningState"
  }

  sensitive_body = length(var.configuration_protected_settings) > 0 ? {
    properties = {
      configurationProtectedSettings = var.configuration_protected_settings
    }
  } : {}

  sensitive_body_version = length(var.configuration_protected_settings) > 0 ? {
    "properties.configurationProtectedSettings" = var.configuration_protected_settings_version
  } : {}

  dynamic "identity" {
    for_each = var.managed_identities.system_assigned ? ["SystemAssigned"] : []
    content {
      type = identity.value
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
# Identity role assignments
# -----------------------------------------------------------------------------
# AzAPI has no equivalent of azurerm's `role_definition_name`, so role names are
# resolved against a subscription-scope listing, as the AVM interfaces module
# does.
#
# Assignment names are random UUIDs. ARM makes the name the resource identity,
# so deriving it from the principal would let an unknown-at-plan-time principal
# ID force a replacement. `name` is exposed for callers adopting an existing
# assignment.
#
# Granted to the EXTENSION's identity, and not gated on
# `managed_identities.system_assigned`: on AKS the resource provider assigns an
# identity whether or not one was asked for. The second precondition covers the
# case where neither identity exists.

data "azapi_resource_list" "role_definitions" {
  count = length(local.role_definition_names) > 0 ? 1 : 0

  parent_id = local.provider_subscription_resource_id
  type      = "Microsoft.Authorization/roleDefinitions@2022-04-01"
  response_export_values = {
    results = "value[].{id: id, role_name: properties.roleName}"
  }
}

resource "random_uuid" "identity_role_assignment_name" {
  for_each = var.identity_role_assignments
}

resource "azapi_resource" "identity_role_assignments" {
  for_each = var.identity_role_assignments

  name      = coalesce(each.value.name, random_uuid.identity_role_assignment_name[each.key].result)
  parent_id = coalesce(each.value.scope, var.cluster_resource_id)
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  body = {
    properties = {
      condition                          = each.value.condition
      conditionVersion                   = each.value.condition_version
      delegatedManagedIdentityResourceId = each.value.delegated_managed_identity_resource_id
      description                        = each.value.description
      principalId                        = local.extension_principal_id
      principalType                      = "ServicePrincipal"
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
        identity_role_assignments["${each.key}"] names the role
        "${each.value.role_definition_id_or_name}", which matched no role definition.

        Pass a role's display name exactly as Azure spells it, or a full
        role-definition resource ID. Names resolve against the roleDefinitions
        catalogue of the provider's subscription, so a CUSTOM role defined in a
        different subscription is not listed there and must be passed as an ID.
      EOT
    }

    precondition {
      # The principal is unknown until apply, so this is checked then, not at plan.
      condition     = local.extension_principal_id != null
      error_message = <<-EOT
        identity_role_assignments["${each.key}"] has no principal to grant to: this
        extension exposes neither an AKS-assigned identity nor a system-assigned one.

        On AKS the resource provider assigns one to extension types that need it.
        Elsewhere, set `managed_identities = { system_assigned = true }`. If the
        extension type has no identity at all, grant the role outside this module
        to whatever principal it does authenticate as.
      EOT
    }
  }
}
