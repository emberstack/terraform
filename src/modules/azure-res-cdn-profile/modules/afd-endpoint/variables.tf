# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "cdn_profile_resource_id" {
  type        = string
  description = "Resource ID of the Front Door profile the endpoint belongs to — the parent module's `resource_id`."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Cdn/profiles/[^/]+$", var.cdn_profile_resource_id))
    error_message = "cdn_profile_resource_id must be a Microsoft.Cdn/profiles resource ID."
  }
}

variable "name" {
  type        = string
  description = "Endpoint name — the first label of its `azurefd.net` hostname. With `TenantReuse` it must be unique across every profile in the tenant."
  nullable    = false

  # Microsoft.Cdn's rule for its child resources: alphanumerics and hyphens,
  # starting and ending alphanumeric (resource-name-rules table).
  validation {
    condition     = can(regex("^[a-zA-Z0-9]+(-*[a-zA-Z0-9])*$", var.name))
    error_message = "name must be letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

# -----------------------------------------------------------------------------
# Optional — endpoint
# -----------------------------------------------------------------------------

variable "enabled" {
  type        = bool
  default     = true
  description = "Serve traffic on the endpoint. Disabling it takes every route on it offline together."
  nullable    = false
}

variable "domain_name_label_scope" {
  type        = string
  default     = "TenantReuse"
  description = <<-EOT
    Where the hostname's hash is reused when an endpoint of the same name is
    recreated: `TenantReuse` (Azure's default), `SubscriptionReuse`,
    `ResourceGroupReuse` or `NoReuse`.

    ⚠️ It cannot change on an existing endpoint, so a different value replaces
    the endpoint — and its hostname.
  EOT
  nullable    = false

  validation {
    condition     = contains(["TenantReuse", "SubscriptionReuse", "ResourceGroupReuse", "NoReuse"], var.domain_name_label_scope)
    error_message = "domain_name_label_scope must be one of: TenantReuse, SubscriptionReuse, ResourceGroupReuse, NoReuse."
  }
}

# -----------------------------------------------------------------------------
# Optional — routes
# -----------------------------------------------------------------------------

variable "routes" {
  type = map(object({
    origin_group_resource_id   = string
    patterns_to_match          = optional(list(string), ["/*"])
    supported_protocols        = optional(list(string), ["Https"])
    https_redirect_enabled     = optional(bool, false)
    forwarding_protocol        = optional(string, "HttpsOnly")
    origin_path                = optional(string, null)
    link_to_default_domain     = optional(bool, true)
    custom_domain_resource_ids = optional(list(string), [])
    rule_set_resource_ids      = optional(list(string), [])
    enabled                    = optional(bool, true)
    cache = optional(object({
      query_string_caching_behavior = optional(string, "IgnoreQueryString")
      query_parameters              = optional(string, null)
      compression_enabled           = optional(bool, false)
      content_types_to_compress     = optional(list(string), [])
      duration                      = optional(string, null)
      behavior                      = optional(string, "OverrideAlways")
    }), null)
  }))
  default     = {}
  description = <<-EOT
    Routes on the endpoint, keyed by route name.

    - `origin_group_resource_id`: the `resource_id` of a `modules/origin-group`.
    - `patterns_to_match`: paths the route accepts, e.g. `/*` or `/files/*`.
    - `supported_protocols`: `Https`, `Http` or both. Defaults to HTTPS only.
    - `https_redirect_enabled`: redirect HTTP to HTTPS — needs `Http` accepted.
    - `forwarding_protocol`: `HttpsOnly`, `HttpOnly` or `MatchRequest`. An origin
      group with managed-identity authentication needs `HttpsOnly`.
    - `origin_path`: a path prefix on the origin, e.g. `/maintenance`.
    - `link_to_default_domain`: serve on the endpoint's `azurefd.net` hostname.
    - `custom_domain_resource_ids`: existing `customDomains` of the same
      profile.
    - `rule_set_resource_ids`: the `resource_id`s of `modules/rule-set`s on
      the same profile, run in list order before the `duration` rule set.
    - `cache`: null serves every request from the origin. Otherwise
      `query_string_caching_behavior` is `IgnoreQueryString`, `UseQueryString`,
      `IgnoreSpecifiedQueryStrings` or `IncludeSpecifiedQueryStrings`, the last
      two naming `query_parameters` (comma separated).
      - `duration`: a fixed cache lifetime, `[d.]hh:mm:ss` up to 366 days (e.g.
        `00:01:00`). Null leaves the lifetime to the origin's `Cache-Control`,
        or one to three days without one. Set, it creates a rule set named
        `<route key without hyphens>cache` on the profile, attached to this
        route.
      - `behavior`: with `duration`, `OverrideAlways` (ignore the origin) or
        `OverrideIfOriginMissing` (only when the origin sends no lifetime).
        Responses marked `no-store`, `no-cache` or `private` are never cached.

    ⚠️ Leave `cache` null on a route whose origin answers per caller: a cached
    response is served to the next client whatever credentials it sent.
  EOT
  nullable    = false

  validation {
    condition = alltrue([
      for name in keys(var.routes) : length(name) <= 50 && can(regex("^[a-zA-Z0-9]+(-*[a-zA-Z0-9])*$", name))
    ])
    error_message = "routes keys are route names: 1-50 characters of letters, digits and hyphens, starting and ending with a letter or digit."
  }

  validation {
    condition = alltrue([
      for route in values(var.routes) :
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Cdn/profiles/[^/]+/originGroups/[^/]+$", route.origin_group_resource_id))
    ])
    error_message = "routes origin_group_resource_id must be a Microsoft.Cdn/profiles/originGroups resource ID."
  }

  validation {
    condition = alltrue([
      for route in values(var.routes) :
      length(route.patterns_to_match) > 0 && alltrue([for pattern in route.patterns_to_match : startswith(pattern, "/")])
    ])
    error_message = "routes patterns_to_match must be non-empty, and every pattern must start with /."
  }

  validation {
    condition = alltrue([
      for route in values(var.routes) :
      length(route.supported_protocols) > 0 && alltrue([for protocol in route.supported_protocols : contains(["Http", "Https"], protocol)])
    ])
    error_message = "routes supported_protocols must be a non-empty list of Http and Https."
  }

  validation {
    condition     = alltrue([for route in values(var.routes) : !route.https_redirect_enabled || contains(route.supported_protocols, "Http")])
    error_message = "routes https_redirect_enabled needs Http in supported_protocols — the redirect answers HTTP requests."
  }

  validation {
    condition     = alltrue([for route in values(var.routes) : contains(["HttpsOnly", "HttpOnly", "MatchRequest"], route.forwarding_protocol)])
    error_message = "routes forwarding_protocol must be one of: HttpsOnly, HttpOnly, MatchRequest."
  }

  validation {
    condition     = alltrue([for route in values(var.routes) : route.origin_path == null || startswith(coalesce(route.origin_path, "/"), "/")])
    error_message = "routes origin_path must start with / when set."
  }

  validation {
    condition     = alltrue([for route in values(var.routes) : route.link_to_default_domain || length(route.custom_domain_resource_ids) > 0])
    error_message = "routes with link_to_default_domain = false need at least one custom domain, or nothing serves them."
  }

  validation {
    condition = alltrue(flatten([
      for route in values(var.routes) : [
        for id in route.custom_domain_resource_ids :
        can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Cdn/profiles/[^/]+/customDomains/[^/]+$", id))
      ]
    ]))
    error_message = "routes custom_domain_resource_ids must be Microsoft.Cdn/profiles/customDomains resource IDs."
  }

  validation {
    condition = alltrue(flatten([
      for route in values(var.routes) : [
        for id in route.rule_set_resource_ids :
        can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Cdn/profiles/[^/]+/ruleSets/[^/]+$", id))
      ]
    ]))
    error_message = "routes rule_set_resource_ids must be Microsoft.Cdn/profiles/ruleSets resource IDs."
  }

  validation {
    condition = alltrue([
      for route in values(var.routes) : route.cache == null || contains(
        ["IgnoreQueryString", "UseQueryString", "IgnoreSpecifiedQueryStrings", "IncludeSpecifiedQueryStrings"],
        try(route.cache.query_string_caching_behavior, "")
      )
    ])
    error_message = "routes cache.query_string_caching_behavior must be one of: IgnoreQueryString, UseQueryString, IgnoreSpecifiedQueryStrings, IncludeSpecifiedQueryStrings."
  }

  validation {
    condition = alltrue([
      for route in values(var.routes) : route.cache == null || (
        endswith(try(route.cache.query_string_caching_behavior, ""), "SpecifiedQueryStrings") == (try(route.cache.query_parameters, null) != null)
      )
    ])
    error_message = "routes cache.query_parameters is required with IgnoreSpecifiedQueryStrings and IncludeSpecifiedQueryStrings, and must be null otherwise."
  }

  validation {
    condition = alltrue([
      for route in values(var.routes) : route.cache == null || (
        try(route.cache.compression_enabled, false) || length(try(route.cache.content_types_to_compress, [])) == 0
      )
    ])
    error_message = "routes cache.content_types_to_compress can only be set with compression_enabled = true."
  }

  validation {
    condition = alltrue([
      for route in values(var.routes) : try(route.cache.duration, null) == null || (
        can(regex("^([0-9]+\\.)?([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$", try(route.cache.duration, ""))) &&
        tonumber(coalesce(try(regex("^([0-9]+)\\.", try(route.cache.duration, ""))[0], null), "0")) <= 366
      )
    ])
    error_message = "routes cache.duration must be [d.]hh:mm:ss, at most 366 days (e.g. 00:01:00)."
  }

  validation {
    condition = alltrue([
      for route in values(var.routes) : route.cache == null || contains(["OverrideAlways", "OverrideIfOriginMissing"], try(route.cache.behavior, ""))
    ])
    error_message = "routes cache.behavior must be OverrideAlways or OverrideIfOriginMissing."
  }

  # The duration's rule set is named from the route key, under the rule-set
  # name rule: a letter, then letters and digits, at most 60 in all.
  validation {
    condition = alltrue([
      for key, route in var.routes : try(route.cache.duration, null) == null || can(regex("^[a-zA-Z][a-zA-Z0-9]{0,54}$", replace(key, "-", "")))
    ])
    error_message = "routes keys with cache.duration must start with a letter and be at most 55 letters and digits once hyphens are removed, because they name the route's rule set."
  }
}

# -----------------------------------------------------------------------------
# Optional — WAF
# -----------------------------------------------------------------------------

variable "security_policy" {
  type = object({
    name                       = optional(string, null)
    waf_policy_resource_id     = string
    patterns_to_match          = optional(list(string), ["/*"])
    custom_domain_resource_ids = optional(list(string), [])
  })
  default     = null
  description = <<-EOT
    Puts a Front Door WAF policy in front of the endpoint. Null attaches none.

    - `name`: defaults to `<name>-waf`. It is a profile-level name, so it must be
      unique within the profile.
    - `waf_policy_resource_id`: a `Microsoft.Network/frontDoorWebApplicationFirewallPolicies`
      ID whose SKU matches the profile's.
    - `patterns_to_match`: paths the policy inspects.
    - `custom_domain_resource_ids`: custom domains to cover besides the
      endpoint's own. A domain can sit in only one security policy.
  EOT

  validation {
    condition     = var.security_policy == null || can(regex("^[a-zA-Z0-9]+(-*[a-zA-Z0-9])*$", coalesce(try(var.security_policy.name, null), "default")))
    error_message = "security_policy.name must be letters, digits and hyphens, starting and ending with a letter or digit."
  }

  validation {
    condition = var.security_policy == null || can(regex(
      "(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/frontDoorWebApplicationFirewallPolicies/[^/]+$",
      try(var.security_policy.waf_policy_resource_id, "")
    ))
    error_message = "security_policy.waf_policy_resource_id must be a Microsoft.Network/frontDoorWebApplicationFirewallPolicies resource ID."
  }

  validation {
    condition = var.security_policy == null || (
      length(try(var.security_policy.patterns_to_match, [])) > 0 &&
      alltrue([for pattern in try(var.security_policy.patterns_to_match, []) : startswith(pattern, "/")])
    )
    error_message = "security_policy.patterns_to_match must be non-empty, and every pattern must start with /."
  }

  validation {
    condition = var.security_policy == null || alltrue([
      for id in try(var.security_policy.custom_domain_resource_ids, []) :
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Cdn/profiles/[^/]+/customDomains/[^/]+$", id))
    ])
    error_message = "security_policy.custom_domain_resource_ids must be Microsoft.Cdn/profiles/customDomains resource IDs."
  }
}

# -----------------------------------------------------------------------------
# Optional — metadata
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the endpoint. Routes and the security policy carry none."
}
