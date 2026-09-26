# =============================================================================
# FIREWALL POLICY RULE COLLECTION GROUP
# (Microsoft.Network/firewallPolicies/ruleCollectionGroups)
# =============================================================================
# One rule collection group on an existing firewall policy. A policy's groups
# usually have different owners — platform rules, per-workload rules, DNAT for
# one service — so each is a unit of its own rather than an input on the policy.
#
# ARM keeps a group's collections, and each collection's rules, as arrays whose
# items carry a `name`, and azapi matches them by that name rather than by
# position. Adding or removing a collection is therefore planned as exactly
# that, not as every later collection shifting one slot.
#
# Every write locks the policy, so groups in one configuration are written one
# at a time — ARM rejects concurrent writes to one policy's groups. A lock only
# spans one Terraform run; another configuration writing to the same policy at
# the same time is what `var.retry` is for.
# =============================================================================

locals {
  nat_rule_collections = [
    for name, collection in var.nat_rule_collections : {
      # ARM stores and returns the action as `Dnat`, while the REST specification
      # spells the enum `DNAT`. azapi compares strings exactly, so the stored
      # casing is sent.
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
  ]

  network_rule_collections = [
    for name, collection in var.network_rule_collections : {
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
  ]

  application_rule_collections = [
    for name, collection in var.application_rule_collections : {
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
  ]

  collection_names = concat(
    keys(var.nat_rule_collections),
    keys(var.network_rule_collections),
    keys(var.application_rule_collections),
  )
}

resource "azapi_resource" "this" {
  name      = var.name
  parent_id = var.firewall_policy_resource_id
  type      = "Microsoft.Network/firewallPolicies/ruleCollectionGroups@2025-07-01"
  body = {
    properties = {
      priority = var.priority
      ruleCollections = concat(
        local.nat_rule_collections,
        local.network_rule_collections,
        local.application_rule_collections,
      )
    }
  }
  # Unset rule fields are null. ARM materialises every one of them — empty lists,
  # an empty description, `false` flags — so without this each would diff
  # against its null forever.
  ignore_null_property = true
  locks                = [var.firewall_policy_resource_id]
  # Nothing reads the response, and it repeats every rule; exporting none of it
  # keeps a large group's state from doubling.
  response_export_values = {}
  retry                  = var.retry

  timeouts {
    create = var.timeouts.create
    delete = var.timeouts.delete
    read   = var.timeouts.read
    update = var.timeouts.update
  }

  lifecycle {
    precondition {
      # All three kinds share one `ruleCollections` array, matched by name.
      condition     = length(distinct(local.collection_names)) == length(local.collection_names)
      error_message = "Rule collection names must be unique across nat_rule_collections, network_rule_collections and application_rule_collections."
    }
  }
}
