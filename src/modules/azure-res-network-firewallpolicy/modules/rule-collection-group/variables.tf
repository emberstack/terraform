# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "firewall_policy_resource_id" {
  type        = string
  description = "Resource ID of the firewall policy the group belongs to — the parent module's `resource_id`."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/firewallPolicies/[^/]+$", var.firewall_policy_resource_id))
    error_message = "firewall_policy_resource_id must be a Microsoft.Network/firewallPolicies resource ID."
  }
}

variable "name" {
  type        = string
  description = "Name of the rule collection group."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9._-]{0,78}[a-zA-Z0-9_])?$", var.name))
    error_message = "name must be 1-80 characters of letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }
}

variable "priority" {
  type        = number
  description = "Priority of the group within the policy, 100-65000. Lower is evaluated first."
  nullable    = false

  validation {
    condition     = floor(var.priority) == var.priority && var.priority >= 100 && var.priority <= 65000
    error_message = "priority must be a whole number from 100 to 65000."
  }
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "nat_rule_collections" {
  type = map(object({
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
  }))
  default     = {}
  description = <<-EOT
    DNAT rule collections, keyed by collection name.

    - `destination_address`: the firewall public IP the traffic arrives on.
    - `protocols`: `TCP` and/or `UDP`.
    - `translated_address` or `translated_fqdn`: exactly one — where the traffic goes.

    Rules are a list: their order is kept as given.
  EOT
  nullable    = false

  validation {
    condition     = alltrue([for collection in values(var.nat_rule_collections) : floor(collection.priority) == collection.priority && collection.priority >= 100 && collection.priority <= 65000])
    error_message = "nat_rule_collections priorities must be whole numbers from 100 to 65000."
  }

  # Rules are matched to ARM's copy by name, so a duplicate would make two
  # rules indistinguishable.
  validation {
    condition     = alltrue([for collection in values(var.nat_rule_collections) : length(distinct([for rule in collection.rules : rule.name])) == length(collection.rules)])
    error_message = "Rule names must be unique within each of nat_rule_collections."
  }

  validation {
    condition = alltrue(flatten([
      for collection in values(var.nat_rule_collections) : [
        for rule in collection.rules : (rule.translated_address == null) != (rule.translated_fqdn == null)
      ]
    ]))
    error_message = "Each NAT rule needs exactly one of translated_address or translated_fqdn."
  }

  validation {
    condition = alltrue(flatten([
      for collection in values(var.nat_rule_collections) : [
        for rule in collection.rules : [for protocol in rule.protocols : contains(["TCP", "UDP"], protocol)]
      ]
    ]))
    error_message = "NAT rule protocols must be TCP or UDP."
  }
}

variable "network_rule_collections" {
  type = map(object({
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
  }))
  default     = {}
  description = <<-EOT
    Network (L4) rule collections, keyed by collection name.

    - `action`: `Allow` or `Deny`.
    - `protocols`: `TCP`, `UDP`, `ICMP` or `Any`.
    - `destination_fqdns`: needs DNS proxy enabled on the policy.

    Rules are a list: their order is kept as given.
  EOT
  nullable    = false

  validation {
    condition     = alltrue([for collection in values(var.network_rule_collections) : floor(collection.priority) == collection.priority && collection.priority >= 100 && collection.priority <= 65000])
    error_message = "network_rule_collections priorities must be whole numbers from 100 to 65000."
  }

  # Rules are matched to ARM's copy by name, so a duplicate would make two
  # rules indistinguishable.
  validation {
    condition     = alltrue([for collection in values(var.network_rule_collections) : length(distinct([for rule in collection.rules : rule.name])) == length(collection.rules)])
    error_message = "Rule names must be unique within each of network_rule_collections."
  }

  validation {
    condition     = alltrue([for collection in values(var.network_rule_collections) : contains(["Allow", "Deny"], collection.action)])
    error_message = "network_rule_collections action must be Allow or Deny."
  }

  validation {
    condition = alltrue(flatten([
      for collection in values(var.network_rule_collections) : [
        for rule in collection.rules : [for protocol in rule.protocols : contains(["TCP", "UDP", "ICMP", "Any"], protocol)]
      ]
    ]))
    error_message = "Network rule protocols must be TCP, UDP, ICMP or Any."
  }
}

variable "application_rule_collections" {
  type = map(object({
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
  }))
  default     = {}
  description = <<-EOT
    Application (L7) rule collections, keyed by collection name.

    - `action`: `Allow` or `Deny`.
    - `protocols`: each `{ type, port }`, with `type` `Http` or `Https`.
    - `destination_fqdns` is sent as ARM's `targetFqdns`, `destination_urls` as
      `targetUrls` — the names differ from network rules' `destinationFqdns`.

    Rules are a list: their order is kept as given.
  EOT
  nullable    = false

  validation {
    condition     = alltrue([for collection in values(var.application_rule_collections) : floor(collection.priority) == collection.priority && collection.priority >= 100 && collection.priority <= 65000])
    error_message = "application_rule_collections priorities must be whole numbers from 100 to 65000."
  }

  # Rules are matched to ARM's copy by name, so a duplicate would make two
  # rules indistinguishable.
  validation {
    condition     = alltrue([for collection in values(var.application_rule_collections) : length(distinct([for rule in collection.rules : rule.name])) == length(collection.rules)])
    error_message = "Rule names must be unique within each of application_rule_collections."
  }

  validation {
    condition     = alltrue([for collection in values(var.application_rule_collections) : contains(["Allow", "Deny"], collection.action)])
    error_message = "application_rule_collections action must be Allow or Deny."
  }

  validation {
    condition = alltrue(flatten([
      for collection in values(var.application_rule_collections) : [
        for rule in collection.rules : [for protocol in rule.protocols : contains(["Http", "Https"], protocol.type)]
      ]
    ]))
    error_message = "Application rule protocol types must be Http or Https."
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
  description = "Retry the write when the error message matches one of `error_message_regex` — for another configuration writing to the same policy at the same time, which the module's own lock cannot see. Bounded by `timeouts`. Null disables it."
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
    create = optional(string, "30m")
    read   = optional(string, "5m")
    update = optional(string, "30m")
    delete = optional(string, "30m")
  })
  default     = {}
  description = "Operation timeouts for the group. The defaults match the azurerm provider's; raise them when `retry` is set, since the timeout is what bounds retrying."
  nullable    = false
}
