# =============================================================================
# AZURE PUBLIC IP ADDRESS (Microsoft.Network/publicIPAddresses)
# =============================================================================
# A Standard or StandardV2 address, always static — the Basic SKU is retired,
# and both remaining SKUs allocate statically only.
#
# ARM returns `zones` in an order of its own — ["2", "3", "1"] for a request of
# ["1", "2", "3"] — and azapi compares a list of strings position by position.
# Zones cannot change once the address exists, so `body.zones` is taken from
# state after creation; a write then resends ARM's own ordering of the same set.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The input stays a plain resource group name (AVM's shape); the subscription
  # comes from the configured provider, so an aliased or multi-subscription
  # caller still lands in the right place.
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
}

# -----------------------------------------------------------------------------
# Public IP address
# -----------------------------------------------------------------------------
# `idleTimeoutInMinutes`, `ipTags` and the DDoS mode are always sent, at Azure's
# own defaults unless overridden, because ARM echoes them back. Optional objects
# (`dnsSettings`, `publicIPPrefix`, the DDoS plan) are null when unused: ARM
# omits them from the response, so null matches instead of diffing.

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Network/publicIPAddresses@2025-07-01"
  body = {
    properties = {
      ddosSettings = {
        ddosProtectionPlan = var.ddos_protection_plan_resource_id == null ? null : {
          id = var.ddos_protection_plan_resource_id
        }
        protectionMode = var.ddos_protection_mode
      }
      dnsSettings = var.domain_name_label == null && var.reverse_fqdn == null ? null : {
        domainNameLabel      = var.domain_name_label
        domainNameLabelScope = var.domain_name_label_scope
        reverseFqdn          = var.reverse_fqdn
      }
      idleTimeoutInMinutes     = var.idle_timeout_in_minutes
      ipTags                   = [for type, tag in var.ip_tags : { ipTagType = type, tag = tag }]
      publicIPAddressVersion   = var.ip_version
      publicIPAllocationMethod = "Static"
      publicIPPrefix = var.public_ip_prefix_resource_id == null ? null : {
        id = var.public_ip_prefix_resource_id
      }
    }
    sku = {
      name = var.sku
      tier = var.sku_tier
    }
    # A non-zonal address carries no `zones` at all; an empty list would be sent
    # as a request for one.
    zones = length(var.zones) > 0 ? var.zones : null
  }
  response_export_values = {
    fqdn       = "properties.dnsSettings.fqdn"
    ip_address = "properties.ipAddress"
  }
  tags = var.tags

  lifecycle {
    # See the banner: ARM reorders zones, and they cannot change in place.
    ignore_changes = [body.zones]
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
