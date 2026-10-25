# =============================================================================
# DNS FORWARDING RULESET RULES
# =============================================================================
# Adds forwarding rules to a DNS forwarding ruleset owned elsewhere, so several
# owners can each contribute rules to one shared ruleset without any of them
# redeclaring it. The ruleset has no inline rule list for an owner to clobber —
# rules exist only as child resources.
#
# Target servers are a list, not the IP-keyed map AVM's resolver module takes:
# the resolver sends to the FIRST target until it stops responding, so order is
# behaviour, and a map would re-sort the targets by address.
# =============================================================================

resource "azapi_resource" "this" {
  for_each = var.rules

  name      = coalesce(each.value.name, each.key)
  parent_id = var.dns_forwarding_ruleset_resource_id
  type      = "Microsoft.Network/dnsForwardingRulesets/forwardingRules@2025-05-01"
  body = {
    properties = {
      domainName          = each.value.domain_name
      forwardingRuleState = each.value.enabled ? "Enabled" : "Disabled"
      metadata            = each.value.metadata
      targetDnsServers = [
        for server in each.value.target_dns_servers : {
          ipAddress = server.ip_address
          port      = server.port
        }
      ]
    }
  }
}
