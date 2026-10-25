# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "dns_forwarding_ruleset_resource_id" {
  type        = string
  description = "ARM resource ID of the existing DNS forwarding ruleset. Used directly as each rule's `parent_id`."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.network/dnsforwardingrulesets/[^/]+$", var.dns_forwarding_ruleset_resource_id))
    error_message = "dns_forwarding_ruleset_resource_id must be an ARM resource ID of a DNS forwarding ruleset, e.g. /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/dnsForwardingRulesets/<ruleset>."
  }
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "rules" {
  type = map(object({
    name        = optional(string)
    domain_name = string
    target_dns_servers = list(object({
      ip_address = string
      port       = optional(number, 53)
    }))
    enabled  = optional(bool, true)
    metadata = optional(map(string))
  }))
  default     = {}
  nullable    = false
  description = <<-EOT
    Map of forwarding rules to create in the ruleset, keyed by a stable identifier. The map key
    is the `for_each` address and the output key, and the rule's ARM name when `name` is unset.

    Fields:
    - `name` (optional) — ARM rule name; defaults to the map key. Must begin with a letter and
      contain only letters, numbers, underscores and dashes.
    - `domain_name` (required) — the dot-terminated namespace the rule matches, e.g.
      `contoso.com.`, or `.` for a wildcard rule. Up to 34 labels.
    - `target_dns_servers` (required) — DNS servers the query is forwarded to, IN ORDER: the
      resolver uses the first target until it stops responding, so put the primary first.
      `port` defaults to 53.
    - `enabled` (optional) — sent as `forwardingRuleState` `Enabled` or `Disabled`. A disabled
      rule is ignored by the resolver. Defaults to true.
    - `metadata` (optional) — string key/value pairs attached to the rule.
  EOT

  validation {
    condition     = alltrue([for k, v in var.rules : can(regex("^[A-Za-z][A-Za-z0-9_-]*$", coalesce(v.name, k)))])
    error_message = "Each rule name (its `name`, or the map key when unset) must begin with a letter and contain only letters, numbers, underscores and dashes."
  }

  # ARM names are case-insensitive, so two entries differing only in case would
  # address the same rule and overwrite each other on every apply.
  validation {
    condition     = length(distinct([for k, v in var.rules : lower(coalesce(v.name, k))])) == length(var.rules)
    error_message = "Rule names must be unique within the ruleset, compared case-insensitively."
  }

  validation {
    condition = alltrue([
      for k, v in var.rules : v.domain_name == "." || (
        endswith(v.domain_name, ".") && length(split(".", trimsuffix(v.domain_name, "."))) <= 34 && !strcontains(v.domain_name, "..")
      )
    ])
    error_message = "Each rule's `domain_name` must be dot-terminated (e.g. contoso.com.) with at most 34 labels, or a single `.` for a wildcard rule."
  }

  validation {
    condition     = alltrue([for k, v in var.rules : length(v.target_dns_servers) > 0])
    error_message = "Each rule needs at least one entry in `target_dns_servers`."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.rules : [
        for server in v.target_dns_servers : can(cidrhost("${server.ip_address}/${strcontains(server.ip_address, ":") ? 128 : 32}", 0))
      ]
    ]))
    error_message = "Each `target_dns_servers` ip_address must be a single IPv4 or IPv6 address, without a prefix length."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.rules : [for server in v.target_dns_servers : server.port >= 1 && server.port <= 65535 && floor(server.port) == server.port]
    ]))
    error_message = "Each `target_dns_servers` port must be an integer from 1 to 65535."
  }
}
