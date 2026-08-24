# =============================================================================
# PRIVATE ENDPOINT (Microsoft.Network/privateEndpoints)
# =============================================================================
# A private endpoint whose target is owned somewhere else. Modules that wrap a
# private-linkable service carry their own `private_endpoints` input; reach for
# this one when nothing in the configuration owns the far end — a Private Link
# Service published by another tenant, or a PaaS resource managed elsewhere.
#
# ARM splits approval across two mutually exclusive body properties.
# `privateLinkServiceConnections` auto-approves and needs write access on the
# target; `manualPrivateLinkServiceConnections` raises a request its owner
# approves out of band, the only path across a tenant boundary. Both are always
# sent, one populated and one empty — an ARM write is a full replace, so
# omitting the unused one would strand the previous connection when
# `is_manual_connection` flips.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The subscription the provider is configured against. Used to list the
  # roleDefinitions catalogue. Built-in roles are present in every subscription,
  # so this resolves any built-in name; a CUSTOM role defined in a different
  # subscription is not in this listing and must be passed as a resource ID.
  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"

  # A private endpoint must be created in the same subscription as the virtual
  # network it attaches to, while the resource it targets may sit in a different
  # one (private-endpoint-overview, properties 4 and 5). The input stays a plain
  # resource group name (AVM's shape), but it resolves in the SUBNET's
  # subscription rather than the provider's, so a caller whose provider is
  # aliased elsewhere still lands beside its virtual network.
  subnet_subscription_resource_id = join("/", slice(split("/", var.subnet_resource_id), 0, 3))
  resource_group_resource_id      = "${local.subnet_subscription_resource_id}/resourceGroups/${var.resource_group_name}"

  # One connection, dropped into whichever of the two arrays `is_manual_connection`
  # selects. `requestMessage` is only read on the manual path, so it is nulled out
  # on the automatic one. ARM carries a resource ID and an alias in the SAME
  # `privateLinkServiceId` property, telling them apart by shape — checked
  # 2026-08-24 against a live alias-based endpoint, which returns the alias there.
  private_link_service_connection = {
    name = coalesce(var.private_service_connection_name, "${var.name}-psc")
    properties = {
      groupIds             = var.subresource_names
      privateLinkServiceId = coalesce(var.private_connection_resource_id, var.private_connection_resource_alias)
      requestMessage       = var.is_manual_connection ? var.request_message : null
    }
  }

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
# Private endpoint
# -----------------------------------------------------------------------------
# `applicationSecurityGroups` live in the private endpoint body — ARM has no
# separate association resource for them.

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Network/privateEndpoints@2025-07-01"
  body = {
    properties = {
      applicationSecurityGroups = [
        for asg_id in values(var.application_security_group_associations) : { id = asg_id }
      ]
      customNetworkInterfaceName = var.network_interface_name
      ipConfigurations = [for ip in values(var.ip_configurations) : {
        name = ip.name
        properties = {
          groupId          = ip.subresource_name
          memberName       = ip.member_name
          privateIPAddress = ip.private_ip_address
        }
      }]
      manualPrivateLinkServiceConnections = var.is_manual_connection ? [local.private_link_service_connection] : []
      privateLinkServiceConnections       = var.is_manual_connection ? [] : [local.private_link_service_connection]
      subnet = {
        id = var.subnet_resource_id
      }
    }
  }
  # ARM returns "" for an unset customNetworkInterfaceName, which would diff
  # against the null this sends. The same applies to requestMessage on the
  # automatic path.
  ignore_null_property = true
  response_export_values = {
    custom_dns_configs = "properties.customDnsConfigs"
    network_interfaces = "properties.networkInterfaces"
    # Exported whole rather than indexed, so the automatic path — where the
    # manual array comes back empty, and vice versa — degrades to a `try` in the
    # outputs instead of failing the export.
    connections        = "properties.privateLinkServiceConnections"
    manual_connections = "properties.manualPrivateLinkServiceConnections"
  }
  tags = var.tags
}

# -----------------------------------------------------------------------------
# DNS zone group
# -----------------------------------------------------------------------------
# ARM models the DNS zone group as a child of the private endpoint. Each config
# is named after its zone, matching what the portal and azurerm produce.
#
# A zone group on a still-Pending manual connection is legal and creates no
# records — ARM has no address to publish until the far side approves.

resource "azapi_resource" "dns_zone_group" {
  count = var.manage_dns_zone_group && length(var.private_dns_zone_resource_ids) > 0 ? 1 : 0

  name      = var.private_dns_zone_group_name
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2025-07-01"
  body = {
    properties = {
      privateDnsZoneConfigs = [for zone_id in var.private_dns_zone_resource_ids : {
        name = basename(zone_id)
        properties = {
          privateDnsZoneId = zone_id
        }
      }]
    }
  }
  response_export_values = { record_sets = "properties.privateDnsZoneConfigs[].recordSets[]" }
}

# -----------------------------------------------------------------------------
# Management lock
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
