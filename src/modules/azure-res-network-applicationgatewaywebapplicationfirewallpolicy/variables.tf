# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "WAF policy name."
  nullable    = false

  # Length from the ARM schema (max 128); characters from the Microsoft.Network
  # rule shared by applicationGateways and firewallPolicies: alphanumerics,
  # underscores, periods and hyphens, starting alphanumeric and ending
  # alphanumeric or underscore.
  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9._-]{0,126}[a-zA-Z0-9_])?$", var.name))
    error_message = "name must be 1-128 characters of letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group where the policy will be created. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the policy. It must match the region of the gateway it is attached to."
  nullable    = false
}

variable "managed_rules" {
  type = object({
    managed_rule_sets = list(object({
      type    = optional(string, "Microsoft_DefaultRuleSet")
      version = string

      # Key = rule group name (e.g. "SQLI"); inner key = rule ID (e.g. "942100").
      rule_group_overrides = optional(map(object({
        rules = map(object({
          enabled = optional(bool, false)
          action  = optional(string)
        }))
      })), {})
    }))

    exclusions = optional(list(object({
      match_variable          = string
      selector                = string
      selector_match_operator = string

      excluded_rule_set = optional(object({
        type    = optional(string, "Microsoft_DefaultRuleSet")
        version = optional(string, "2.1")
        rule_groups = optional(list(object({
          rule_group_name = string
          excluded_rules  = optional(list(string), [])
        })), [])
      }))
    })), [])
  })
  description = <<-EOT
    Managed rule sets, per-rule overrides and exclusions.

    `managed_rule_sets[*].rule_group_overrides` is keyed by rule group name, and each
    group's `rules` by rule ID. A listed rule is DISABLED unless `enabled = true`, which
    is ARM's own default for an override with no state. `action` replaces the rule's
    action (e.g. `Log` to stop a rule contributing to the anomaly score).

    `exclusions[*].excluded_rule_set` scopes an exclusion to rule groups or rules; without
    it the exclusion applies to every rule. A rule group with no `excluded_rules` excludes
    the whole group. The set's `version` defaults to "2.1", the only DRS version
    Application Gateway for Containers supports.
  EOT
  nullable    = false

  validation {
    condition     = length(var.managed_rules.managed_rule_sets) > 0
    error_message = "managed_rules.managed_rule_sets must contain at least one rule set; ARM requires it."
  }

  validation {
    condition = alltrue([
      for rule_set in var.managed_rules.managed_rule_sets :
      contains(["Microsoft_BotManagerRuleSet", "Microsoft_DefaultRuleSet", "Microsoft_HTTPDDoSRuleSet", "OWASP"], rule_set.type)
    ])
    error_message = "managed_rules.managed_rule_sets[*].type must be one of: Microsoft_BotManagerRuleSet, Microsoft_DefaultRuleSet, Microsoft_HTTPDDoSRuleSet, OWASP."
  }

  validation {
    condition = (
      length(distinct([for rule_set in var.managed_rules.managed_rule_sets : rule_set.type])) ==
      length(var.managed_rules.managed_rule_sets)
    )
    error_message = "managed_rules.managed_rule_sets must not list the same rule set type twice."
  }

  # ARM reads an override group with no rules as "disable every rule in the group".
  # Requiring the rules to be listed keeps a missing map from silently switching a
  # whole group off.
  validation {
    condition = alltrue(flatten([
      for rule_set in var.managed_rules.managed_rule_sets : [
        for group in values(rule_set.rule_group_overrides) : length(group.rules) > 0
      ]
    ]))
    error_message = "Every managed_rules rule_group_overrides entry must list at least one rule; an empty override disables the whole rule group."
  }

  validation {
    condition = alltrue(flatten([
      for rule_set in var.managed_rules.managed_rule_sets : [
        for group in values(rule_set.rule_group_overrides) : [
          for rule in values(group.rules) :
          rule.action == null || contains(["Allow", "AnomalyScoring", "Block", "CAPTCHA", "JSChallenge", "Log"], rule.action)
        ]
      ]
    ]))
    error_message = "managed_rules override `action` must be one of: Allow, AnomalyScoring, Block, CAPTCHA, JSChallenge, Log."
  }

  validation {
    condition = alltrue([
      for exclusion in var.managed_rules.exclusions :
      contains([
        "RequestArgKeys", "RequestArgNames", "RequestArgValues",
        "RequestCookieKeys", "RequestCookieNames", "RequestCookieValues",
        "RequestHeaderKeys", "RequestHeaderNames", "RequestHeaderValues",
      ], exclusion.match_variable)
    ])
    error_message = "managed_rules.exclusions[*].match_variable must be one of the Request{Arg,Cookie,Header}{Keys,Names,Values} variables."
  }

  validation {
    condition = alltrue([
      for exclusion in var.managed_rules.exclusions :
      contains(["Contains", "EndsWith", "Equals", "EqualsAny", "StartsWith"], exclusion.selector_match_operator)
    ])
    error_message = "managed_rules.exclusions[*].selector_match_operator must be one of: Contains, EndsWith, Equals, EqualsAny, StartsWith."
  }

  validation {
    condition = alltrue([
      for exclusion in var.managed_rules.exclusions :
      exclusion.excluded_rule_set == null || contains(["Microsoft_BotManagerRuleSet", "Microsoft_DefaultRuleSet", "OWASP"], exclusion.excluded_rule_set.type)
    ])
    error_message = "managed_rules.exclusions[*].excluded_rule_set.type must be one of: Microsoft_BotManagerRuleSet, Microsoft_DefaultRuleSet, OWASP."
  }
}

# -----------------------------------------------------------------------------
# Optional — policy settings
# -----------------------------------------------------------------------------

variable "policy_settings" {
  type = object({
    enabled                                   = optional(bool, true)
    mode                                      = optional(string, "Prevention")
    request_body_check                        = optional(bool, true)
    request_body_enforcement                  = optional(bool, true)
    max_request_body_size_in_kb               = optional(number, 128)
    request_body_inspect_limit_in_kb          = optional(number, 128)
    file_upload_limit_in_mb                   = optional(number, 100)
    file_upload_enforcement                   = optional(bool, true)
    js_challenge_cookie_expiration_in_minutes = optional(number, 30)

    log_scrubbing = optional(object({
      enabled = optional(bool, true)
      rules = optional(list(object({
        enabled                 = optional(bool, true)
        match_variable          = string
        selector_match_operator = optional(string, "Equals")
        selector                = optional(string)
      })), [])
    }))
  })
  default     = {}
  description = <<-EOT
    Policy-wide settings. The defaults are Azure's own: enabled, Prevention mode, request
    body inspection and enforcement at 128 KB, file uploads limited to 100 MB, and a
    30-minute JavaScript challenge cookie. `log_scrubbing` is left out of the body when null.
  EOT
  nullable    = false

  validation {
    condition     = contains(["Detection", "Prevention"], var.policy_settings.mode)
    error_message = "policy_settings.mode must be Detection or Prevention."
  }

  validation {
    condition     = var.policy_settings.max_request_body_size_in_kb >= 8 && var.policy_settings.request_body_inspect_limit_in_kb >= 8
    error_message = "policy_settings.max_request_body_size_in_kb and request_body_inspect_limit_in_kb must be at least 8."
  }

  validation {
    condition     = var.policy_settings.file_upload_limit_in_mb >= 0
    error_message = "policy_settings.file_upload_limit_in_mb must not be negative."
  }

  validation {
    condition     = var.policy_settings.js_challenge_cookie_expiration_in_minutes >= 5 && var.policy_settings.js_challenge_cookie_expiration_in_minutes <= 1440
    error_message = "policy_settings.js_challenge_cookie_expiration_in_minutes must be between 5 and 1440."
  }

  validation {
    condition = var.policy_settings.log_scrubbing == null || alltrue([
      for rule in var.policy_settings.log_scrubbing.rules :
      contains([
        "RequestArgNames", "RequestCookieNames", "RequestHeaderNames",
        "RequestIPAddress", "RequestJSONArgNames", "RequestPostArgNames",
      ], rule.match_variable) && contains(["Equals", "EqualsAny"], rule.selector_match_operator)
    ])
    error_message = "policy_settings.log_scrubbing rules need a match_variable of RequestArgNames, RequestCookieNames, RequestHeaderNames, RequestIPAddress, RequestJSONArgNames or RequestPostArgNames, and a selector_match_operator of Equals or EqualsAny."
  }

  validation {
    condition = var.policy_settings.log_scrubbing == null || alltrue([
      for rule in var.policy_settings.log_scrubbing.rules :
      rule.selector_match_operator != "Equals" || rule.match_variable == "RequestIPAddress" || rule.selector != null
    ])
    error_message = "policy_settings.log_scrubbing rules with selector_match_operator = \"Equals\" need a selector (RequestIPAddress excepted)."
  }
}

# -----------------------------------------------------------------------------
# Optional — custom rules
# -----------------------------------------------------------------------------

variable "custom_rules" {
  type = map(object({
    priority             = number
    action               = string
    rule_type            = optional(string, "MatchRule")
    enabled              = optional(bool, true)
    rate_limit_duration  = optional(string)
    rate_limit_threshold = optional(number)
    group_rate_limit_by  = optional(string)

    match_conditions = list(object({
      match_variables = list(object({
        variable_name = string
        selector      = optional(string)
      }))
      operator           = string
      match_values       = optional(list(string), [])
      negation_condition = optional(bool, false)
      transforms         = optional(list(string), [])
    }))
  }))
  default     = {}
  description = <<-EOT
    Custom rules, keyed by rule name. They are evaluated before the managed rule sets, in
    ascending `priority` (1-100, unique). Conditions within a rule are ANDed.

    `rate_limit_duration`, `rate_limit_threshold` and `group_rate_limit_by` apply only to
    `rule_type = "RateLimitRule"`, where the first two are required.
  EOT
  nullable    = false

  validation {
    condition     = length(var.custom_rules) <= 100
    error_message = "custom_rules supports at most 100 rules per policy."
  }

  validation {
    condition     = alltrue([for name in keys(var.custom_rules) : length(name) >= 1 && length(name) <= 128])
    error_message = "custom_rules keys (rule names) must be 1-128 characters."
  }

  validation {
    condition     = alltrue([for rule in values(var.custom_rules) : rule.priority >= 1 && rule.priority <= 100 && floor(rule.priority) == rule.priority])
    error_message = "custom_rules priority must be a whole number between 1 and 100."
  }

  validation {
    condition     = length(distinct([for rule in values(var.custom_rules) : rule.priority])) == length(var.custom_rules)
    error_message = "custom_rules priorities must be unique."
  }

  validation {
    condition     = alltrue([for rule in values(var.custom_rules) : contains(["MatchRule", "RateLimitRule"], rule.rule_type)])
    error_message = "custom_rules rule_type must be MatchRule or RateLimitRule."
  }

  validation {
    condition     = alltrue([for rule in values(var.custom_rules) : contains(["Allow", "Block", "CAPTCHA", "JSChallenge", "Log"], rule.action)])
    error_message = "custom_rules action must be one of: Allow, Block, CAPTCHA, JSChallenge, Log."
  }

  validation {
    condition = alltrue([
      for rule in values(var.custom_rules) :
      rule.rule_type == "RateLimitRule" ? (
        rule.rate_limit_duration != null && rule.rate_limit_threshold != null
        ) : (
        rule.rate_limit_duration == null && rule.rate_limit_threshold == null && rule.group_rate_limit_by == null
      )
    ])
    error_message = "custom_rules: RateLimitRule needs rate_limit_duration and rate_limit_threshold; MatchRule must not set rate_limit_duration, rate_limit_threshold or group_rate_limit_by."
  }

  validation {
    condition = alltrue([
      for rule in values(var.custom_rules) :
      (rule.rate_limit_duration == null || contains(["FiveMins", "OneMin"], rule.rate_limit_duration)) &&
      (rule.rate_limit_threshold == null || rule.rate_limit_threshold >= 1) &&
      (rule.group_rate_limit_by == null || contains(["ClientAddr", "ClientAddrXFFHeader", "GeoLocation", "GeoLocationXFFHeader", "None"], rule.group_rate_limit_by))
    ])
    error_message = "custom_rules: rate_limit_duration must be OneMin or FiveMins, rate_limit_threshold at least 1, and group_rate_limit_by one of ClientAddr, ClientAddrXFFHeader, GeoLocation, GeoLocationXFFHeader, None."
  }

  validation {
    condition     = alltrue([for rule in values(var.custom_rules) : length(rule.match_conditions) > 0])
    error_message = "custom_rules: every rule needs at least one match condition."
  }

  validation {
    condition = alltrue(flatten([
      for rule in values(var.custom_rules) : [
        for condition in rule.match_conditions :
        length(condition.match_variables) > 0 && alltrue([
          for variable in condition.match_variables :
          contains(["PostArgs", "QueryString", "RemoteAddr", "RequestBody", "RequestCookies", "RequestHeaders", "RequestMethod", "RequestUri"], variable.variable_name)
        ])
      ]
    ]))
    error_message = "custom_rules match_variables must be non-empty, with variable_name one of: PostArgs, QueryString, RemoteAddr, RequestBody, RequestCookies, RequestHeaders, RequestMethod, RequestUri."
  }

  validation {
    condition = alltrue(flatten([
      for rule in values(var.custom_rules) : [
        for condition in rule.match_conditions :
        contains([
          "Any", "BeginsWith", "Contains", "EndsWith", "Equal", "GeoMatch",
          "GreaterThan", "GreaterThanOrEqual", "IPMatch", "LessThan", "LessThanOrEqual", "Regex",
        ], condition.operator) && (condition.operator == "Any" || length(condition.match_values) > 0)
      ]
    ]))
    error_message = "custom_rules match_conditions need a valid operator (Any, BeginsWith, Contains, EndsWith, Equal, GeoMatch, GreaterThan, GreaterThanOrEqual, IPMatch, LessThan, LessThanOrEqual, Regex) and, except for Any, at least one match value."
  }

  validation {
    condition = alltrue(flatten([
      for rule in values(var.custom_rules) : [
        for condition in rule.match_conditions : [
          for transform in condition.transforms :
          contains(["HtmlEntityDecode", "Lowercase", "RemoveNulls", "Trim", "Uppercase", "UrlDecode", "UrlEncode"], transform)
        ]
      ]
    ]))
    error_message = "custom_rules transforms must be from: HtmlEntityDecode, Lowercase, RemoveNulls, Trim, Uppercase, UrlDecode, UrlEncode."
  }
}

# -----------------------------------------------------------------------------
# Optional — access
# -----------------------------------------------------------------------------

variable "role_assignments" {
  type = map(object({
    name                                   = optional(string, null)
    role_definition_id_or_name             = string
    principal_id                           = string
    description                            = optional(string, null)
    condition                              = optional(string, null)
    condition_version                      = optional(string, null)
    delegated_managed_identity_resource_id = optional(string, null)
    principal_type                         = optional(string, null)
  }))
  default     = {}
  description = <<-EOT
    Map of policy-scope role assignments, keyed by a stable identifier.

    `role_definition_id_or_name` accepts either:
    - a full role definition resource ID (`/subscriptions/.../providers/Microsoft.Authorization/roleDefinitions/<uuid>`), or
    - a built-in role name (e.g., `Network Contributor`), resolved by a subscription-scope lookup.

    `name` is the assignment's ARM name (a GUID). Leave it unset — a random UUID is generated — unless you
    are adopting an assignment that already exists, where the existing GUID must be supplied to avoid a
    destroy-and-recreate.

    Set `principal_type = "ServicePrincipal"` when the principal is a service principal or a managed
    identity, so ARM skips the directory lookup that fails on a principal created moments earlier.

    Do not edit `principal_id` or `role_definition_id_or_name` on an existing key — ARM rejects the update.
    Add a new key and remove the old one instead.

    Mirrors AVM's standard `role_assignments` interface block.
  EOT
  nullable    = false

  validation {
    condition = alltrue([
      for assignment in var.role_assignments :
      assignment.name == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", assignment.name))
    ])
    error_message = "role_assignments `name`, when supplied, must be a lowercase GUID (e.g. 11111111-1111-1111-1111-111111111111)."
  }
}

# -----------------------------------------------------------------------------
# Optional — metadata
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the WAF policy."
}
