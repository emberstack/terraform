# =============================================================================
# FIREWALL POLICY RULE COLLECTION GROUPS (PATTERN)
# (Microsoft.Network/firewallPolicies/ruleCollectionGroups)
# =============================================================================
# Many rule collection groups on an existing firewall policy, from one map.
# `azure-res-network-firewallpolicy/modules/rule-collection-group` is the same
# resource one group at a time; reach for this when one configuration owns a
# set of groups together. The body is built inline rather than by calling that
# submodule, so this module stays self-contained when copied on its own.
#
# ARM keeps a group's collections, and each collection's rules, as arrays whose
# items carry a `name`, and azapi matches them by that name rather than by
# position. Adding or removing a collection is therefore planned as exactly
# that, not as every later collection shifting one slot.
#
# Every write locks the policy, so the groups are written one at a time — ARM
# rejects concurrent writes to one policy's groups. A lock only spans one
# Terraform run; another configuration writing to the same policy at the same
# time is what `var.retry` is for.
# =============================================================================

locals {
  rule_collections = {
    for key, group in var.groups : key => concat(
      [
        for name, collection in group.nat_rule_collections : {
          # ARM stores and returns the action as `Dnat`, while the REST
          # specification spells the enum `DNAT`. azapi compares strings exactly,
          # so the stored casing is sent.
          action = {
            type = "Dnat"
          }
          name               = name
          priority           = collection.priority
          ruleCollectionType = "FirewallPolicyNatRuleCollection"
          rules = [
            for rule in collection.rules : {
              description          = rule.description
              destinationAddresses = [rule.destination_address]
              destinationPorts     = rule.destination_ports
              ipProtocols          = rule.protocols
              name                 = rule.name
              ruleType             = "NatRule"
              sourceAddresses      = rule.source_addresses
              sourceIpGroups       = rule.source_ip_groups
              translatedAddress    = rule.translated_address
              translatedFqdn       = rule.translated_fqdn
              translatedPort       = rule.translated_port
            }
          ]
        }
      ],
      [
        for name, collection in group.network_rule_collections : {
          action = {
            type = collection.action
          }
          name               = name
          priority           = collection.priority
          ruleCollectionType = "FirewallPolicyFilterRuleCollection"
          rules = [
            for rule in collection.rules : {
              description          = rule.description
              destinationAddresses = rule.destination_addresses
              destinationFqdns     = rule.destination_fqdns
              destinationIpGroups  = rule.destination_ip_groups
              destinationPorts     = rule.destination_ports
              ipProtocols          = rule.protocols
              name                 = rule.name
              ruleType             = "NetworkRule"
              sourceAddresses      = rule.source_addresses
              sourceIpGroups       = rule.source_ip_groups
            }
          ]
        }
      ],
      [
        for name, collection in group.application_rule_collections : {
          action = {
            type = collection.action
          }
          name               = name
          priority           = collection.priority
          ruleCollectionType = "FirewallPolicyFilterRuleCollection"
          rules = [
            for rule in collection.rules : {
              description = rule.description
              fqdnTags    = rule.destination_fqdn_tags
              name        = rule.name
              protocols = [
                for protocol in rule.protocols : {
                  port         = protocol.port
                  protocolType = protocol.type
                }
              ]
              ruleType        = "ApplicationRule"
              sourceAddresses = rule.source_addresses
              sourceIpGroups  = rule.source_ip_groups
              targetFqdns     = rule.destination_fqdns
              targetUrls      = rule.destination_urls
              terminateTLS    = rule.terminate_tls
              webCategories   = rule.web_categories
            }
          ]
        }
      ],
    )
  }

  # The policy lock writes the groups one at a time, and each group's deadline
  # starts when Terraform starts it — not when it gets the lock — so the time it
  # spends queued counts against it. Measured on a ten-group policy: about four
  # minutes per group, and with a flat 30-minute deadline the eighth to tenth
  # groups ran out of time while still waiting. Each group therefore gets 30
  # minutes for every group in the map.
  serialised_timeout = "${30 * max(length(var.groups), 1)}m"

  collection_names = {
    for key, group in var.groups : key => concat(
      keys(group.nat_rule_collections),
      keys(group.network_rule_collections),
      keys(group.application_rule_collections),
    )
  }
}

resource "azapi_resource" "this" {
  for_each = var.groups

  name      = coalesce(each.value.name, each.key)
  parent_id = var.firewall_policy_resource_id
  type      = "Microsoft.Network/firewallPolicies/ruleCollectionGroups@2025-07-01"
  body = {
    properties = {
      priority        = each.value.priority
      ruleCollections = local.rule_collections[each.key]
    }
  }
  # Unset rule fields are null. ARM materialises every one of them — empty lists,
  # an empty description, `false` flags — so without this each would diff
  # against its null forever.
  ignore_null_property = true
  locks                = [var.firewall_policy_resource_id]
  # Nothing reads the response, and it repeats every rule; exporting none of it
  # keeps large groups' state from doubling.
  response_export_values = {}
  retry                  = var.retry

  timeouts {
    create = coalesce(var.timeouts.create, local.serialised_timeout)
    delete = coalesce(var.timeouts.delete, local.serialised_timeout)
    read   = var.timeouts.read
    update = coalesce(var.timeouts.update, local.serialised_timeout)
  }

  lifecycle {
    precondition {
      # All three kinds share one `ruleCollections` array, matched by name.
      condition     = length(distinct(local.collection_names[each.key])) == length(local.collection_names[each.key])
      error_message = "groups[\"${each.key}\"]: rule collection names must be unique across nat_rule_collections, network_rule_collections and application_rule_collections."
    }
  }
}
