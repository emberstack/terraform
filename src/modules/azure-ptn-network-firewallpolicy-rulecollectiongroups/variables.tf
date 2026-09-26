variable "firewall_policy_resource_id" {
  type        = string
  description = "Resource ID of the firewall policy the groups belong to — e.g. `azure-res-network-firewallpolicy`'s `resource_id`."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/firewallPolicies/[^/]+$", var.firewall_policy_resource_id))
    error_message = "firewall_policy_resource_id must be a Microsoft.Network/firewallPolicies resource ID."
  }
}

variable "groups" {
  type = map(object({
    name     = optional(string, null)
    priority = number
    nat_rule_collections = optional(map(object({
      priority = number
      rules = list(object({
        name                = string
        protocols           = list(string)
        destination_address = string
        destination_ports   = list(string)
        translated_port     = string
        translated_address  = optional(string, null)
        translated_fqdn     = optional(string, null)
        source_addresses    = optional(list(string), null)
        source_ip_groups    = optional(list(string), null)
        description         = optional(string, null)
      }))
    })), {})
    network_rule_collections = optional(map(object({
      priority = number
      action   = optional(string, "Allow")
      rules = list(object({
        name                  = string
        protocols             = list(string)
        destination_ports     = list(string)
        source_addresses      = optional(list(string), null)
        source_ip_groups      = optional(list(string), null)
        destination_addresses = optional(list(string), null)
        destination_ip_groups = optional(list(string), null)
        destination_fqdns     = optional(list(string), null)
        description           = optional(string, null)
      }))
    })), {})
    application_rule_collections = optional(map(object({
      priority = number
      action   = optional(string, "Allow")
      rules = list(object({
        name = string
        protocols = list(object({
          type = string
          port = number
        }))
        source_addresses      = optional(list(string), null)
        source_ip_groups      = optional(list(string), null)
        destination_fqdns     = optional(list(string), null)
        destination_urls      = optional(list(string), null)
        destination_fqdn_tags = optional(list(string), null)
        web_categories        = optional(list(string), null)
        terminate_tls         = optional(bool, null)
        description           = optional(string, null)
      }))
    })), {})
  }))
  default     = {}
  description = <<-EOT
    Rule collection groups on the policy, keyed by a stable identifier. Each group's
    shape is `modules/rule-collection-group` of `azure-res-network-firewallpolicy`,
    with `firewall_policy_resource_id` shared:

    - `name`: the group's ARM name. Defaults to the key.
    - `priority`: 100-65000, lower evaluated first.
    - `nat_rule_collections`: DNAT, keyed by collection name. Each rule has exactly one
      of `translated_address` or `translated_fqdn`; protocols `TCP` and/or `UDP`.
    - `network_rule_collections`: L4, keyed by collection name. `action` `Allow` or
      `Deny`; protocols `TCP`, `UDP`, `ICMP` or `Any`.
    - `application_rule_collections`: L7, keyed by collection name. `action` `Allow`
      or `Deny`; each protocol `{ type, port }` with `type` `Http` or `Https`.

    Rules are lists and keep the order given. An empty map creates no groups, so a
    caller can switch a group on and off by including or omitting its entry.
  EOT
  nullable    = false

  validation {
    condition = alltrue([
      for key, group in var.groups :
      can(regex("^[a-zA-Z0-9]([a-zA-Z0-9._-]{0,78}[a-zA-Z0-9_])?$", coalesce(group.name, key)))
    ])
    error_message = "Each group's name (or key, when name is unset) must be 1-80 characters of letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }

  validation {
    condition     = length(distinct([for key, group in var.groups : coalesce(group.name, key)])) == length(var.groups)
    error_message = "Group names (or keys, when name is unset) must be unique — two entries would address the same ARM resource."
  }

  validation {
    condition = alltrue(concat(
      [for group in values(var.groups) : floor(group.priority) == group.priority && group.priority >= 100 && group.priority <= 65000],
      flatten([
        for group in values(var.groups) : [
          for collection in concat(values(group.nat_rule_collections), values(group.network_rule_collections), values(group.application_rule_collections)) :
          floor(collection.priority) == collection.priority && collection.priority >= 100 && collection.priority <= 65000
        ]
      ]),
    ))
    error_message = "Group and collection priorities must be whole numbers from 100 to 65000."
  }

  validation {
    condition = alltrue(flatten([
      for group in values(var.groups) : [
        for collection in values(group.nat_rule_collections) : [
          for rule in collection.rules : (rule.translated_address == null) != (rule.translated_fqdn == null)
        ]
      ]
    ]))
    error_message = "Each NAT rule needs exactly one of translated_address or translated_fqdn."
  }

  validation {
    condition = alltrue(flatten([
      for group in values(var.groups) : [
        [for collection in values(group.nat_rule_collections) : [for rule in collection.rules : [for protocol in rule.protocols : contains(["TCP", "UDP"], protocol)]]],
        [for collection in values(group.network_rule_collections) : [for rule in collection.rules : [for protocol in rule.protocols : contains(["TCP", "UDP", "ICMP", "Any"], protocol)]]],
        [for collection in values(group.application_rule_collections) : [for rule in collection.rules : [for protocol in rule.protocols : contains(["Http", "Https"], protocol.type)]]],
      ]
    ]))
    error_message = "Rule protocols must be TCP or UDP for NAT rules; TCP, UDP, ICMP or Any for network rules; Http or Https for application rules."
  }

  validation {
    condition = alltrue(flatten([
      for group in values(var.groups) : [
        for collection in concat(values(group.network_rule_collections), values(group.application_rule_collections)) : contains(["Allow", "Deny"], collection.action)
      ]
    ]))
    error_message = "Network and application rule collection actions must be Allow or Deny."
  }

  # Rules are matched to ARM's copy by name, so a duplicate would make two
  # rules indistinguishable.
  validation {
    condition = alltrue(flatten([
      for group in values(var.groups) : [
        for collection in concat(values(group.nat_rule_collections), values(group.network_rule_collections), values(group.application_rule_collections)) :
        length(distinct([for rule in collection.rules : rule.name])) == length(collection.rules)
      ]
    ]))
    error_message = "Rule names must be unique within each collection."
  }
}

variable "retry" {
  type = object({
    error_message_regex  = list(string)
    interval_seconds     = optional(number)
    max_interval_seconds = optional(number)
    multiplier           = optional(number)
    randomization_factor = optional(number)
  })
  description = "Retry a group's write when the error message matches one of `error_message_regex` — for another configuration writing to the same policy at the same time, which the module's own lock cannot see. Bounded by `timeouts`. Null disables it."
  default     = null

  validation {
    condition     = var.retry == null || length(try(var.retry.error_message_regex, [])) > 0
    error_message = "retry.error_message_regex must contain at least one pattern; leave retry null to disable retrying."
  }

  # regexall, not regex: regex() errors when the pattern does not match, so
  # can(regex(p, "")) would reject every pattern not present in the empty
  # string — which is all of them.
  validation {
    condition     = var.retry == null || alltrue([for pattern in try(var.retry.error_message_regex, []) : can(regexall(pattern, ""))])
    error_message = "every retry.error_message_regex entry must be a valid regular expression."
  }
}

variable "timeouts" {
  type = object({
    create = optional(string, null)
    read   = optional(string, "5m")
    update = optional(string, null)
    delete = optional(string, null)
  })
  default     = {}
  description = <<-EOT
    Operation timeouts for each group. Unset, create, update and delete default to
    30 minutes — the azurerm provider's — for EVERY group in the map, since a group's
    deadline includes its wait behind the others on the policy lock. Raise them
    further when `retry` is set, since the timeout is also what bounds retrying.
  EOT
  nullable    = false
}
