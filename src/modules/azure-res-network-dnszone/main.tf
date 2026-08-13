# =============================================================================
# AZURE PUBLIC DNS ZONE (Microsoft.Network/dnsZones)
# =============================================================================
# Mirrors the AVM `Azure/avm-res-network-dnszone/azurerm` module's input shape
# (`name`, `resource_group_name`, `tags`, `role_assignments`) and adds two
# capabilities AVM does not yet support:
#   - SOA record customization (email, TTLs, tags)
#   - parent-zone NS delegation (creates the NS record in the parent zone)
#
# Public DNS zones are global (location-less) — no `location` input.
#
# Public DNS record sets capitalize their ARM properties (`TTL`, `NSRecords`,
# `SOARecord`, `minimumTTL`) where the private DNS API does not (`ttl`,
# `aRecords`, `soaRecord`, `minimumTtl`). The two families do not share bodies.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The input stays a plain resource group name (AVM's shape); the subscription
  # comes from the configured provider, so an aliased or multi-subscription
  # caller still lands in the right place.
  subscription_resource_id   = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  resource_group_resource_id = "${local.subscription_resource_id}/resourceGroups/${var.resource_group_name}"

  # Sorted so both the delegation body and the output are order-stable no matter
  # what order ARM lists the zone's name servers in. NS entries are a set.
  #
  # `terraform import` does not apply `response_export_values`, so during an
  # import the export is absent and this has to tolerate it. Every other command
  # refreshes first and gets the real list; the delegation's precondition is what
  # stops an empty one from ever reaching ARM.
  name_servers = sort(try(azapi_resource.this.output.name_servers, []))

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

# -----------------------------------------------------------------------------
# Public DNS zone
# -----------------------------------------------------------------------------

resource "azapi_resource" "this" {
  location  = "global"
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Network/dnsZones@2018-05-01"
  # Everything ARM returns under `properties` — the name servers, the record-set
  # counters, `zoneType` — is read-only, so there is nothing to send.
  body                   = { properties = {} }
  response_export_values = { name_servers = "properties.nameServers" }
  tags                   = var.tags
}

# -----------------------------------------------------------------------------
# SOA record
# -----------------------------------------------------------------------------
# ARM models SOA as a child record set named `@`, not as part of the zone.
# `var.soa_record` defaults every timer to Azure's own value rather than leaving
# it null, because this is written as a full PUT and an omitted timer is reset.
# `host` and `serialNumber` are server-assigned and deliberately not sent.

resource "azapi_resource" "soa" {
  count = var.soa_record != null ? 1 : 0

  name      = "@"
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Network/dnsZones/SOA@2018-05-01"
  body = {
    properties = {
      metadata = var.soa_record.tags
      SOARecord = {
        email       = var.soa_record.email
        expireTime  = var.soa_record.expire_time
        minimumTTL  = var.soa_record.minimum_ttl
        refreshTime = var.soa_record.refresh_time
        retryTime   = var.soa_record.retry_time
      }
      TTL = var.soa_record.ttl
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

  lifecycle {
    precondition {
      # An unresolved name falls through the `lookup` default in
      # `role_definition_resource_ids` and reaches ARM as a bare string in
      # `roleDefinitionId`, which fails with an error naming neither the role nor
      # this assignment. Every resolved value is an ARM ID, so it starts with "/".
      condition     = startswith(local.role_definition_resource_ids[each.key], "/")
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
# Parent zone NS delegation
# -----------------------------------------------------------------------------
# Creates an NS record in the parent zone to delegate this subdomain. The parent
# zone's resource ID is the record's `parent_id` directly. The deploying
# principal must have write access to the parent zone's RG.

resource "azapi_resource" "delegation" {
  count = var.parent_zone != null ? 1 : 0

  name      = var.parent_zone.delegation_name
  parent_id = var.parent_zone.zone_id
  type      = "Microsoft.Network/dnsZones/NS@2018-05-01"
  body = {
    properties = {
      metadata  = var.parent_zone.delegation_tags
      NSRecords = [for nameserver in local.name_servers : { nsdname = nameserver }]
      TTL       = var.parent_zone.delegation_ttl
    }
  }
  response_export_values = { fqdn = "properties.fqdn" }

  lifecycle {
    precondition {
      condition     = length(local.name_servers) > 0
      error_message = "The zone reported no name servers, which would write an empty NS delegation and break resolution for this subdomain. Refresh the zone and retry."
    }
  }
}
