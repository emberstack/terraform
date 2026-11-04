# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "WAF policy name."
  nullable    = false

  # Azure's rule for frontdoorWebApplicationFirewallPolicies: 1-128
  # alphanumerics, starting with a letter — no hyphens (resource-name-rules
  # table, Microsoft.Network).
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,127}$", var.name))
    error_message = "name must be 1-128 letters and digits, starting with a letter."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group where the policy will be created. Mirrors AVM `resource_group_name`. The policy itself is global whatever the group's region."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

# -----------------------------------------------------------------------------
# Optional — tier and settings
# -----------------------------------------------------------------------------

variable "sku" {
  type        = string
  default     = "Standard_AzureFrontDoor"
  description = "Policy tier, which must match the Front Door profile it protects: `Standard_AzureFrontDoor` or `Premium_AzureFrontDoor`. Classic Front Door is not supported."
  nullable    = false

  validation {
    condition     = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.sku)
    error_message = "sku must be one of: Standard_AzureFrontDoor, Premium_AzureFrontDoor."
  }
}

variable "policy_settings" {
  type = object({
    enabled                            = optional(bool, true)
    mode                               = optional(string, "Prevention")
    request_body_check_enabled         = optional(bool, true)
    redirect_url                       = optional(string, null)
    custom_block_response_status_code  = optional(number, null)
    custom_block_response_body         = optional(string, null)
    captcha_expiration_in_minutes      = optional(number, null)
    js_challenge_expiration_in_minutes = optional(number, null)
    log_scrubbing = optional(object({
      enabled = optional(bool, true)
      rules = list(object({
        match_variable          = string
        selector                = optional(string, null)
        selector_match_operator = optional(string, "EqualsAny")
        enabled                 = optional(bool, true)
      }))
    }), null)
  })
  default     = {}
  description = <<-EOT
    Policy-wide settings.

    - `enabled`: switch the whole policy off without detaching it.
    - `mode`: `Prevention` (block) or `Detection` (log only).
    - `request_body_check_enabled`: inspect request bodies.
    - `redirect_url`: target of rules whose action is `Redirect`.
    - `custom_block_response_status_code`, `custom_block_response_body`: what a
      blocked client receives. The body is base64-encoded.
    - `captcha_expiration_in_minutes`, `js_challenge_expiration_in_minutes`: how
      long a passed challenge holds, 5 to 1440.
    - `log_scrubbing`: fields to scrub from WAF logs. `match_variable` is
      `QueryStringArgNames`, `RequestBodyJsonArgNames`, `RequestBodyPostArgNames`,
      `RequestCookieNames`, `RequestHeaderNames`, `RequestIPAddress` or
      `RequestUri`; `selector_match_operator` is `Equals` (naming a `selector`)
      or `EqualsAny`.
  EOT
  nullable    = false

  validation {
    condition     = contains(["Prevention", "Detection"], var.policy_settings.mode)
    error_message = "policy_settings.mode must be Prevention or Detection."
  }

  validation {
    condition     = var.policy_settings.custom_block_response_body == null || can(regex("^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$", coalesce(var.policy_settings.custom_block_response_body, "-")))
    error_message = "policy_settings.custom_block_response_body must be base64-encoded."
  }

  validation {
    condition = alltrue([
      for minutes in compact([
        var.policy_settings.captcha_expiration_in_minutes == null ? "" : tostring(var.policy_settings.captcha_expiration_in_minutes),
        var.policy_settings.js_challenge_expiration_in_minutes == null ? "" : tostring(var.policy_settings.js_challenge_expiration_in_minutes),
      ]) : tonumber(minutes) >= 5 && tonumber(minutes) <= 1440 && floor(tonumber(minutes)) == tonumber(minutes)
    ])
    error_message = "policy_settings captcha_expiration_in_minutes and js_challenge_expiration_in_minutes must be integers from 5 to 1440."
  }

  validation {
    condition = var.policy_settings.log_scrubbing == null || alltrue([
      for rule in try(var.policy_settings.log_scrubbing.rules, []) :
      contains(["QueryStringArgNames", "RequestBodyJsonArgNames", "RequestBodyPostArgNames", "RequestCookieNames", "RequestHeaderNames", "RequestIPAddress", "RequestUri"], rule.match_variable) &&
      contains(["Equals", "EqualsAny"], rule.selector_match_operator) &&
      (rule.selector_match_operator == "Equals") == (rule.selector != null)
    ])
    error_message = "policy_settings.log_scrubbing rules need a valid match_variable, and a selector exactly when selector_match_operator is Equals."
  }
}

# -----------------------------------------------------------------------------
# Optional — rules
# -----------------------------------------------------------------------------

variable "custom_rules" {
  type = map(object({
    priority                       = number
    action                         = string
    enabled                        = optional(bool, true)
    rule_type                      = optional(string, "MatchRule")
    rate_limit_duration_in_minutes = optional(number, 1)
    rate_limit_threshold           = optional(number, null)
    group_by                       = optional(list(string), [])
    match_conditions = list(object({
      match_variable = string
      operator       = string
      match_values   = list(string)
      selector       = optional(string, null)
      negate         = optional(bool, false)
      transforms     = optional(list(string), [])
    }))
  }))
  default     = {}
  description = <<-EOT
    Custom rules, keyed by rule name. Every condition in a rule must match.

    - `priority`: lower runs first; unique across the policy.
    - `action`: `Allow`, `Block`, `Log`, `Redirect`, `JSChallenge` or `CAPTCHA`.
    - `rule_type`: `MatchRule` or `RateLimitRule`.
    - `rate_limit_threshold`, `rate_limit_duration_in_minutes` (1 to 5),
      `group_by` (`SocketAddr`, `GeoLocation`, `None`): rate-limit rules only.
    - `match_conditions`:
      - `match_variable`: `RemoteAddr`, `SocketAddr`, `RequestMethod`,
        `RequestUri`, `QueryString`, `RequestHeader`, `RequestBody`, `PostArgs`,
        `Cookies` or `JA4`.
      - `selector`: the header, cookie or argument name, for the variables that
        take one.
      - `operator`: `Any`, `IPMatch`, `GeoMatch`, `Equal`, `Contains`,
        `BeginsWith`, `EndsWith`, `RegEx`, `LessThan`, `LessThanOrEqual`,
        `GreaterThan`, `GreaterThanOrEqual`, `ServiceTagMatch`, `AsnMatch` or
        `ClientFingerprint`.
      - `transforms`: `Lowercase`, `Uppercase`, `Trim`, `UrlDecode`, `UrlEncode`,
        `RemoveNulls`, applied before matching.
  EOT
  nullable    = false

  validation {
    condition     = alltrue([for name in keys(var.custom_rules) : length(name) > 0 && length(name) <= 128])
    error_message = "custom_rules keys are rule names of 1-128 characters."
  }

  validation {
    condition     = length(distinct([for rule in values(var.custom_rules) : rule.priority])) == length(var.custom_rules)
    error_message = "custom_rules priorities must be unique."
  }

  validation {
    condition = alltrue([
      for rule in values(var.custom_rules) :
      contains(["Allow", "Block", "Log", "Redirect", "JSChallenge", "CAPTCHA"], rule.action) &&
      contains(["MatchRule", "RateLimitRule"], rule.rule_type)
    ])
    error_message = "custom_rules action must be Allow, Block, Log, Redirect, JSChallenge or CAPTCHA, and rule_type MatchRule or RateLimitRule."
  }

  validation {
    condition = alltrue([
      for rule in values(var.custom_rules) : rule.rule_type != "RateLimitRule" || (
        rule.rate_limit_threshold != null &&
        try(rule.rate_limit_threshold >= 1, false) &&
        rule.rate_limit_duration_in_minutes >= 1 && rule.rate_limit_duration_in_minutes <= 5
      )
    ])
    error_message = "custom_rules of type RateLimitRule need rate_limit_threshold >= 1 and rate_limit_duration_in_minutes from 1 to 5."
  }

  validation {
    condition = alltrue([
      for rule in values(var.custom_rules) :
      alltrue([for variable in rule.group_by : contains(["SocketAddr", "GeoLocation", "None"], variable)])
    ])
    error_message = "custom_rules group_by may only contain SocketAddr, GeoLocation and None."
  }

  validation {
    condition = alltrue(flatten([
      for rule in values(var.custom_rules) : [
        for condition in rule.match_conditions :
        contains(["Cookies", "JA4", "PostArgs", "QueryString", "RemoteAddr", "RequestBody", "RequestHeader", "RequestMethod", "RequestUri", "SocketAddr"], condition.match_variable) &&
        contains(["Any", "AsnMatch", "BeginsWith", "ClientFingerprint", "Contains", "EndsWith", "Equal", "GeoMatch", "GreaterThan", "GreaterThanOrEqual", "IPMatch", "LessThan", "LessThanOrEqual", "RegEx", "ServiceTagMatch"], condition.operator) &&
        alltrue([for transform in condition.transforms : contains(["Lowercase", "RemoveNulls", "Trim", "Uppercase", "UrlDecode", "UrlEncode"], transform)])
      ]
    ]))
    error_message = "custom_rules match_conditions need a valid match_variable, operator and transforms — see the variable description for the accepted values."
  }

  validation {
    condition     = alltrue([for rule in values(var.custom_rules) : length(rule.match_conditions) > 0])
    error_message = "custom_rules need at least one match condition each."
  }
}

variable "managed_rule_sets" {
  type = list(object({
    type    = string
    version = string
    action  = optional(string, null)
    exclusions = optional(list(object({
      match_variable          = string
      selector                = string
      selector_match_operator = string
    })), [])
    rule_group_overrides = optional(map(object({
      exclusions = optional(list(object({
        match_variable          = string
        selector                = string
        selector_match_operator = string
      })), [])
      rules = optional(map(object({
        enabled = optional(bool, true)
        action  = optional(string, null)
        exclusions = optional(list(object({
          match_variable          = string
          selector                = string
          selector_match_operator = string
        })), [])
      })), {})
    })), {})
  }))
  default     = []
  description = <<-EOT
    Managed rule sets. Premium only.

    - `type`, `version`: e.g. `Microsoft_DefaultRuleSet` `2.1`, or
      `Microsoft_BotManagerRuleSet` `1.1`.
    - `action`: `Block`, `Log` or `Redirect` — the rule-set action of the
      anomaly-scoring sets (DRS 2.x). Leave null for the others.
    - `exclusions`: request parts the whole set ignores. `match_variable` is
      `QueryStringArgNames`, `RequestBodyJsonArgNames`, `RequestBodyPostArgNames`,
      `RequestCookieNames` or `RequestHeaderNames`; `selector_match_operator` is
      `Equals`, `EqualsAny`, `Contains`, `StartsWith` or `EndsWith`.
    - `rule_group_overrides`: keyed by rule group name, with group-level
      `exclusions` and `rules` keyed by rule ID — `enabled`, `action`
      (`AnomalyScoring` for DRS 2.x rules, or `Allow`, `Block`, `Log`,
      `Redirect`, `JSChallenge`, `CAPTCHA`) and per-rule `exclusions`.
  EOT
  nullable    = false

  validation {
    condition     = length(var.managed_rule_sets) == 0 || var.sku == "Premium_AzureFrontDoor"
    error_message = "managed_rule_sets need sku = \"Premium_AzureFrontDoor\" — Standard runs custom rules only."
  }

  validation {
    condition = alltrue([
      for rule_set in var.managed_rule_sets :
      length(rule_set.type) > 0 && length(rule_set.version) > 0 &&
      (rule_set.action == null || contains(["Block", "Log", "Redirect"], coalesce(rule_set.action, "-")))
    ])
    error_message = "managed_rule_sets need a type and version, and action must be Block, Log or Redirect when set."
  }

  validation {
    condition = alltrue(flatten([
      for rule_set in var.managed_rule_sets : [
        for exclusion in concat(
          rule_set.exclusions,
          flatten([for group in values(rule_set.rule_group_overrides) : group.exclusions]),
          flatten([for group in values(rule_set.rule_group_overrides) : flatten([for rule in values(group.rules) : rule.exclusions])]),
        ) :
        contains(["QueryStringArgNames", "RequestBodyJsonArgNames", "RequestBodyPostArgNames", "RequestCookieNames", "RequestHeaderNames"], exclusion.match_variable) &&
        contains(["Contains", "EndsWith", "Equals", "EqualsAny", "StartsWith"], exclusion.selector_match_operator)
      ]
    ]))
    error_message = "managed_rule_sets exclusions need a valid match_variable and selector_match_operator — see the variable description for the accepted values."
  }

  validation {
    condition = alltrue(flatten([
      for rule_set in var.managed_rule_sets : [
        for group in values(rule_set.rule_group_overrides) : [
          for rule in values(group.rules) :
          rule.action == null || contains(["Allow", "AnomalyScoring", "Block", "CAPTCHA", "JSChallenge", "Log", "Redirect"], coalesce(rule.action, "-"))
        ]
      ]
    ]))
    error_message = "managed_rule_sets override action must be Allow, AnomalyScoring, Block, CAPTCHA, JSChallenge, Log or Redirect when set."
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
    - a built-in role name (e.g., `Reader`), resolved by a subscription-scope lookup.

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

variable "lock" {
  type = object({
    kind = string
    name = optional(string, null)
  })
  default     = null
  description = <<-EOT
    Resource lock configuration.

    - `kind`: `CanNotDelete` or `ReadOnly`.
    - `name`: optional. Defaults to `lock-<policy-name>`.
  EOT

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be one of: CanNotDelete, ReadOnly."
  }
}

# -----------------------------------------------------------------------------
# Optional — metadata
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the policy."
}
