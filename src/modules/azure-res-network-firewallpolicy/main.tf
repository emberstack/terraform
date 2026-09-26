# =============================================================================
# FIREWALL POLICY (Microsoft.Network/firewallPolicies)
# =============================================================================
# The policy is its own top-level resource: a firewall only references it by
# ID, several firewalls can share one, and a policy can inherit from a base
# policy. Rule collection groups are ARM children of the policy, and usually
# have owners of their own, so they live in `modules/rule-collection-group`.
#
# ARM writes are full replaces, and this body models the tier, threat
# intelligence, IDPS, DNS, SNAT private ranges and the base policy. Explicit
# proxy, TLS inspection, insights, the threat intelligence allowlist, the SQL
# redirect and a managed identity are never sent, so a policy carrying any of
# them must not be managed here: the next write replaces the body without them.
#
# Firewall policies do not support diagnostic settings — the firewall emits
# the logs — so, unlike most modules in this family, there is no such input.
#
# Inputs mirror the AVM `Azure/avm-res-network-firewallpolicy/azurerm` names
# where they overlap, over a `resource_group_name` like the rest of this family.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The subscription the provider is configured against. Used to list the
  # roleDefinitions catalogue. Built-in roles are present in every subscription,
  # so this resolves any built-in name; a CUSTOM role defined in a different
  # subscription is not in this listing and must be passed as a resource ID.
  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  resource_group_resource_id        = "${local.provider_subscription_resource_id}/resourceGroups/${var.resource_group_name}"

  intrusion_detection = var.firewall_policy_intrusion_detection == null ? null : {
    configuration = {
      bypassTrafficSettings = [
        for bypass in var.firewall_policy_intrusion_detection.traffic_bypass : {
          description          = bypass.description
          destinationAddresses = bypass.destination_addresses
          destinationIpGroups  = bypass.destination_ip_groups
          destinationPorts     = bypass.destination_ports
          name                 = bypass.name
          protocol             = bypass.protocol
          sourceAddresses      = bypass.source_addresses
          sourceIpGroups       = bypass.source_ip_groups
        }
      ]
      privateRanges = var.firewall_policy_intrusion_detection.private_ranges
      signatureOverrides = [
        for id, mode in var.firewall_policy_intrusion_detection.signature_overrides : {
          id   = id
          mode = mode
        }
      ]
    }
    mode = var.firewall_policy_intrusion_detection.mode
  }

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
# Firewall policy
# -----------------------------------------------------------------------------

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Network/firewallPolicies@2025-07-01"
  body = {
    properties = {
      basePolicy = var.firewall_policy_base_policy_id == null ? null : {
        id = var.firewall_policy_base_policy_id
      }
      dnsSettings = var.firewall_policy_dns == null ? null : {
        enableProxy = var.firewall_policy_dns.proxy_enabled
        servers     = var.firewall_policy_dns.servers
      }
      intrusionDetection = local.intrusion_detection
      sku = {
        tier = var.firewall_policy_sku
      }
      snat = var.firewall_policy_private_ip_ranges == null ? null : {
        privateRanges = var.firewall_policy_private_ip_ranges
      }
      threatIntelMode = var.firewall_policy_threat_intelligence_mode
    }
  }
  # Unset optional blocks, and unset fields inside an IDPS bypass, are null.
  # Dropping the nulls keeps them out of the request and stops ARM's defaults
  # from diffing against them.
  ignore_null_property = true
  # Nothing is exported. Left unset, azapi keeps the WHOLE response in `output`,
  # and a policy's response carries `size`, which moves whenever any of its rule
  # collection groups changes — usually another configuration's apply. Nothing
  # here reads `output`.
  response_export_values = {}
  tags                   = var.tags
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
