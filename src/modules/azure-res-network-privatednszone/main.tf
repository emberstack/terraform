# =============================================================================
# AZURE PRIVATE DNS ZONE (Microsoft.Network/privateDnsZones)
# =============================================================================
# Records and virtual-network links are deliberately not managed here — they
# live in `azure-ptn-network-privatednszone-records`, `modules/vnet-link` and
# `azure-ptn-network-privatednszone-vnet-links`, so that adding or removing one
# never touches zone state. The README compares them.
#
# Zones are global, so there is no `location` input to pick a region with.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The input stays a plain resource group name (AVM's shape); the subscription
  # comes from the configured provider, so an aliased or multi-subscription
  # caller still lands in the right place.
  subscription_resource_id   = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  resource_group_resource_id = "${local.subscription_resource_id}/resourceGroups/${var.resource_group_name}"

  role_definition_name_to_resource_id = length(var.role_assignments) > 0 ? {
    for definition in data.azapi_resource_list.role_definitions[0].output.results : definition.role_name => definition.id
  } : {}

  # An entry that is already a resource ID falls through the lookup untouched.
  role_definition_resource_ids = {
    for k, v in var.role_assignments : k => lookup(
      local.role_definition_name_to_resource_id,
      v.role_definition_id_or_name,
      v.role_definition_id_or_name
    )
  }
}

resource "azapi_resource" "this" {
  location  = "global"
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Network/privateDnsZones@2024-06-01"
  # Everything ARM returns under `properties` — record-set counts, link counts,
  # provisioning state — is read-only, so there is nothing to send.
  body = { properties = {} }
  tags = var.tags
}

# =============================================================================
# SOA RECORD
# =============================================================================
# ARM models SOA as a child record set named `@`, not as part of the zone.
# `var.soa_record` defaults every timer to Azure's own value rather than leaving
# it null, because this is written as a full PUT and an omitted timer is reset.
# `host` and `serialNumber` are server-assigned and deliberately not sent.
# =============================================================================

resource "azapi_resource" "soa" {
  count = var.soa_record != null ? 1 : 0

  name      = "@"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Network/privateDnsZones/SOA@2024-06-01"
  body = {
    properties = {
      metadata = var.soa_record.tags
      soaRecord = {
        email       = var.soa_record.email
        expireTime  = var.soa_record.expire_time
        minimumTtl  = var.soa_record.minimum_ttl
        refreshTime = var.soa_record.refresh_time
        retryTime   = var.soa_record.retry_time
      }
      ttl = var.soa_record.ttl
    }
  }
}

# =============================================================================
# ROLE ASSIGNMENTS (zone scope)
# =============================================================================
# AzAPI has no equivalent of azurerm's `role_definition_name`, so role names are
# resolved against a subscription-scope listing, as the AVM interfaces module
# does.
#
# Assignment names are random UUIDs. ARM makes the name the resource identity,
# so deriving it from the principal would let an unknown-at-plan-time principal
# ID force a replacement. `name` is exposed for callers adopting an existing
# assignment.
# =============================================================================

data "azapi_resource_list" "role_definitions" {
  count = length(var.role_assignments) > 0 ? 1 : 0

  parent_id = local.subscription_resource_id
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
      roleDefinitionId                   = local.role_definition_resource_ids[each.key]
    }
  }
}
