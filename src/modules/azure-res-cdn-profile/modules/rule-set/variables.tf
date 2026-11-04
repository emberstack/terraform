# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "cdn_profile_resource_id" {
  type        = string
  description = "Resource ID of the Front Door profile the rule set belongs to — the parent module's `resource_id`."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Cdn/profiles/[^/]+$", var.cdn_profile_resource_id))
    error_message = "cdn_profile_resource_id must be a Microsoft.Cdn/profiles resource ID."
  }
}

variable "name" {
  type        = string
  description = "Name of the rule set — unique within the profile."
  nullable    = false

  # Rule set names take letters and digits only, no hyphens.
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,59}$", var.name))
    error_message = "name must be 1-60 letters and digits, starting with a letter."
  }
}

# -----------------------------------------------------------------------------
# Optional — rules
# -----------------------------------------------------------------------------

variable "rules" {
  type = map(object({
    order           = number
    stop_evaluating = optional(bool, false)

    conditions = optional(list(object({
      match_variable = string
      operator       = string
      match_values   = optional(list(string), [])
      selector       = optional(string, null)
      negate         = optional(bool, false)
      transforms     = optional(list(string), [])
    })), [])

    route_configuration_override = optional(object({
      origin_group = optional(object({
        resource_id         = string
        forwarding_protocol = optional(string, "HttpsOnly")
      }), null)
      cache = optional(object({
        behavior                      = optional(string, null)
        duration                      = optional(string, null)
        query_string_caching_behavior = optional(string, "IgnoreQueryString")
        query_parameters              = optional(string, null)
        compression_enabled           = optional(bool, false)
      }), null)
    }), null)

    url_rewrite = optional(object({
      source_pattern          = string
      destination             = string
      preserve_unmatched_path = optional(bool, true)
    }), null)

    url_redirect = optional(object({
      redirect_type = optional(string, "Found")
      protocol      = optional(string, "MatchRequest")
      host_name     = optional(string, null)
      path          = optional(string, null)
      query_string  = optional(string, null)
      fragment      = optional(string, null)
    }), null)

    request_headers = optional(list(object({
      action = string
      name   = string
      value  = optional(string, null)
    })), [])

    response_headers = optional(list(object({
      action = string
      name   = string
      value  = optional(string, null)
    })), [])
  }))
  default     = {}
  description = <<-EOT
    Rules in the rule set, keyed by rule name (1-60 letters and digits,
    starting with a letter). At most 100 rules, each with up to 10 conditions
    and 5 actions.

    - `order`: run order, ascending and unique — 0 runs first.
    - `stop_evaluating`: when the rule matches, skip every later rule, in this
      rule set and in every rule set after it on the route.
    - `conditions`: ANDed together; within one condition, `match_values` are
      ORed. Empty runs the rule on every request.
      - `match_variable`: `ClientPort`, `Cookies`, `HostName`, `HttpVersion`,
        `IsDevice`, `PostArgs`, `QueryString`, `RemoteAddress`, `RequestBody`,
        `RequestHeader`, `RequestMethod`, `RequestScheme`, `RequestUri`,
        `ServerPort`, `SocketAddr`, `SslProtocol`, `UrlFileExtension`,
        `UrlFileName` or `UrlPath`.
      - `operator`: `Any`, `Equal`, `Contains`, `BeginsWith`, `EndsWith`,
        `LessThan`, `LessThanOrEqual`, `GreaterThan`, `GreaterThanOrEqual` or
        `RegEx`; `UrlPath` adds `Wildcard`. `RemoteAddress` takes `Any`,
        `IPMatch` or `GeoMatch`, `SocketAddr` `Any` or `IPMatch`, and
        `HttpVersion`, `IsDevice`, `RequestMethod`, `RequestScheme` and
        `SslProtocol` only `Equal` — `negate` gives "not equal".
      - `match_values`: required unless `operator` is `Any`. `UrlPath` values
        have no leading `/`; `RemoteAddress` takes CIDRs (`IPMatch`) or
        country codes (`GeoMatch`).
      - `selector`: the header, cookie or form field to read — required for
        `RequestHeader`, `Cookies` and `PostArgs`, and not allowed otherwise.
      - `transforms`: `Lowercase`, `Uppercase`, `Trim`, `UrlDecode`,
        `UrlEncode` or `RemoveNulls`, applied before matching.
    - `route_configuration_override`: replaces the route's settings for the
      requests it matches.
      - `origin_group`: send them to another origin group of the profile, with
        `forwarding_protocol` `HttpsOnly`, `HttpOnly` or `MatchRequest`. An
        origin group with managed-identity authentication needs `HttpsOnly`.
        Null keeps the route's origin group.
      - `cache`: null turns caching OFF for these requests, whatever the route
        says. Otherwise `behavior` is `HonorOrigin` (the origin's
        `Cache-Control`, or one to three days without one), `OverrideAlways`
        or `OverrideIfOriginMissing` — the last two need `duration`,
        `[d.]hh:mm:ss` up to 366 days, and are the default when it is set.
        `query_string_caching_behavior` and `query_parameters` work as on a
        route.
    - `url_rewrite`: rewrite the path sent to the origin. `source_pattern` is
      a prefix of the path left after the route's pattern; `destination`
      replaces it, followed by the rest of the path unless
      `preserve_unmatched_path` is false.
    - `url_redirect`: answer with a redirect instead of fetching. `redirect_type`
      is `Moved` (301), `Found` (302), `TemporaryRedirect` (307) or
      `PermanentRedirect` (308); `protocol` `MatchRequest`, `Http` or `Https`.
      `host_name`, `path`, `query_string` (no leading `?`) and `fragment` (no
      leading `#`) replace those parts of the URL; null keeps the request's.
      Not combinable with `url_rewrite` or `route_configuration_override` in
      one rule.
    - `request_headers`, `response_headers`: `action` `Append`, `Overwrite`
      or `Delete` on header `name`, with `value` for the first two.

    Server variables such as `{client_ip}` or `{url_path}` work in header
    values, rewrite destinations and redirect parts.
  EOT
  nullable    = false

  validation {
    condition     = length(var.rules) <= 100
    error_message = "rules can hold at most 100 rules."
  }

  validation {
    condition     = alltrue([for name in keys(var.rules) : can(regex("^[a-zA-Z][a-zA-Z0-9]{0,59}$", name))])
    error_message = "rules keys are rule names: 1-60 letters and digits, starting with a letter."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) : rule.order >= 0 && floor(rule.order) == rule.order
    ])
    error_message = "rules order must be a whole number from 0 up."
  }

  validation {
    condition     = length(distinct([for rule in values(var.rules) : rule.order])) == length(var.rules)
    error_message = "rules order must be unique within the rule set."
  }

  # --- conditions ---

  validation {
    condition     = alltrue([for rule in values(var.rules) : length(rule.conditions) <= 10])
    error_message = "rules can have at most 10 conditions each."
  }

  validation {
    condition = alltrue(flatten([
      for rule in values(var.rules) : [
        for condition in rule.conditions : contains(keys(local.condition_type_names), condition.match_variable)
      ]
    ]))
    error_message = "rules conditions match_variable must be one of: ClientPort, Cookies, HostName, HttpVersion, IsDevice, PostArgs, QueryString, RemoteAddress, RequestBody, RequestHeader, RequestMethod, RequestScheme, RequestUri, ServerPort, SocketAddr, SslProtocol, UrlFileExtension, UrlFileName, UrlPath."
  }

  validation {
    condition = alltrue(flatten([
      for rule in values(var.rules) : [
        for condition in rule.conditions :
        contains(lookup(local.condition_operators, condition.match_variable, []), condition.operator)
      ]
    ]))
    error_message = "rules conditions operator is not one this match_variable accepts — see the rules description for each condition's operators."
  }

  validation {
    condition = alltrue(flatten([
      for rule in values(var.rules) : [
        for condition in rule.conditions : condition.operator == "Any" || length(condition.match_values) > 0
      ]
    ]))
    error_message = "rules conditions match_values must be set unless operator is Any."
  }

  validation {
    condition = alltrue(flatten([
      for rule in values(var.rules) : [
        for condition in rule.conditions :
        contains(local.selector_conditions, condition.match_variable) == (condition.selector != null)
      ]
    ]))
    error_message = "rules conditions selector is required for RequestHeader, Cookies and PostArgs, and not allowed for any other match_variable."
  }

  validation {
    condition = alltrue(flatten([
      for rule in values(var.rules) : [
        for condition in rule.conditions : [
          for transform in condition.transforms :
          contains(["Lowercase", "Uppercase", "Trim", "UrlDecode", "UrlEncode", "RemoveNulls"], transform)
        ]
      ]
    ]))
    error_message = "rules conditions transforms must be Lowercase, Uppercase, Trim, UrlDecode, UrlEncode or RemoveNulls."
  }

  validation {
    condition = alltrue(flatten([
      for rule in values(var.rules) : [
        for condition in rule.conditions : [
          for value in condition.match_values :
          condition.match_variable != "RequestMethod" || contains(["GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS", "TRACE"], value)
        ]
      ]
    ]))
    error_message = "rules conditions match_values for RequestMethod must be GET, HEAD, POST, PUT, DELETE, OPTIONS or TRACE."
  }

  validation {
    condition = alltrue(flatten([
      for rule in values(var.rules) : [
        for condition in rule.conditions : [
          for value in condition.match_values :
          (condition.match_variable != "RequestScheme" || contains(["HTTP", "HTTPS"], value)) &&
          (condition.match_variable != "IsDevice" || contains(["Mobile", "Desktop"], value)) &&
          (condition.match_variable != "SslProtocol" || contains(["TLSv1", "TLSv1.1", "TLSv1.2"], value))
        ]
      ]
    ]))
    error_message = "rules conditions match_values must be HTTP or HTTPS for RequestScheme, Mobile or Desktop for IsDevice, and TLSv1, TLSv1.1 or TLSv1.2 for SslProtocol."
  }

  # --- actions ---

  validation {
    condition = alltrue([
      for action_count in [
        for rule in values(var.rules) :
        (rule.route_configuration_override == null ? 0 : 1) +
        (rule.url_rewrite == null ? 0 : 1) +
        (rule.url_redirect == null ? 0 : 1) +
        length(rule.request_headers) +
        length(rule.response_headers)
      ] : action_count >= 1 && action_count <= 5
    ])
    error_message = "rules need 1 to 5 actions each — route_configuration_override, url_rewrite and url_redirect count one each, every header change one."
  }

  # A redirect answers the client itself, so the request never reaches the
  # origin a rewrite or route override would shape.
  validation {
    condition = alltrue([
      for rule in values(var.rules) :
      rule.url_redirect == null || (rule.url_rewrite == null && rule.route_configuration_override == null)
    ])
    error_message = "rules url_redirect cannot be combined with url_rewrite or route_configuration_override in one rule."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) :
      try(rule.route_configuration_override.origin_group, null) == null || (
        can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Cdn/profiles/[^/]+/originGroups/[^/]+$", rule.route_configuration_override.origin_group.resource_id)) &&
        contains(["HttpsOnly", "HttpOnly", "MatchRequest"], rule.route_configuration_override.origin_group.forwarding_protocol)
      )
    ])
    error_message = "rules route_configuration_override.origin_group needs a Microsoft.Cdn/profiles/originGroups resource_id and a forwarding_protocol of HttpsOnly, HttpOnly or MatchRequest."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) :
      try(rule.route_configuration_override.cache, null) == null || (
        contains(["IgnoreQueryString", "UseQueryString", "IgnoreSpecifiedQueryStrings", "IncludeSpecifiedQueryStrings"], rule.route_configuration_override.cache.query_string_caching_behavior) &&
        endswith(rule.route_configuration_override.cache.query_string_caching_behavior, "SpecifiedQueryStrings") == (rule.route_configuration_override.cache.query_parameters != null)
      )
    ])
    error_message = "rules route_configuration_override.cache.query_string_caching_behavior must be IgnoreQueryString, UseQueryString, IgnoreSpecifiedQueryStrings or IncludeSpecifiedQueryStrings, and query_parameters is required with the last two and must be null otherwise."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) :
      try(rule.route_configuration_override.cache.behavior, null) == null ||
      contains(["HonorOrigin", "OverrideAlways", "OverrideIfOriginMissing"], try(rule.route_configuration_override.cache.behavior, ""))
    ])
    error_message = "rules route_configuration_override.cache.behavior must be HonorOrigin, OverrideAlways or OverrideIfOriginMissing."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) :
      try(rule.route_configuration_override.cache.behavior, null) == null ||
      (try(rule.route_configuration_override.cache.behavior, null) == "HonorOrigin") == (try(rule.route_configuration_override.cache.duration, null) == null)
    ])
    error_message = "rules route_configuration_override.cache.duration is required with OverrideAlways and OverrideIfOriginMissing, and must be null with HonorOrigin."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) : try(rule.route_configuration_override.cache.duration, null) == null || (
        can(regex("^([0-9]+\\.)?([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$", try(rule.route_configuration_override.cache.duration, ""))) &&
        tonumber(coalesce(try(regex("^([0-9]+)\\.", try(rule.route_configuration_override.cache.duration, ""))[0], null), "0")) <= 366
      )
    ])
    error_message = "rules route_configuration_override.cache.duration must be [d.]hh:mm:ss, at most 366 days (e.g. 00:01:00)."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) : rule.url_rewrite == null || (
        startswith(try(rule.url_rewrite.source_pattern, ""), "/") && startswith(try(rule.url_rewrite.destination, ""), "/")
      )
    ])
    error_message = "rules url_rewrite source_pattern and destination must start with /."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) : rule.url_redirect == null || (
        contains(["Moved", "Found", "TemporaryRedirect", "PermanentRedirect"], try(rule.url_redirect.redirect_type, "")) &&
        contains(["MatchRequest", "Http", "Https"], try(rule.url_redirect.protocol, ""))
      )
    ])
    error_message = "rules url_redirect redirect_type must be Moved, Found, TemporaryRedirect or PermanentRedirect, and protocol MatchRequest, Http or Https."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) : rule.url_redirect == null || (
        (try(rule.url_redirect.path, null) == null || startswith(coalesce(try(rule.url_redirect.path, null), "/"), "/")) &&
        !startswith(coalesce(try(rule.url_redirect.query_string, null), "x"), "?") &&
        !startswith(coalesce(try(rule.url_redirect.fragment, null), "x"), "#")
      )
    ])
    error_message = "rules url_redirect path must start with /, and query_string and fragment must not start with ? or #."
  }

  validation {
    condition = alltrue(flatten([
      for rule in values(var.rules) : [
        for header in concat(rule.request_headers, rule.response_headers) :
        contains(["Append", "Overwrite", "Delete"], header.action) &&
        length(header.name) > 0 &&
        (header.action == "Delete") == (header.value == null)
      ]
    ]))
    error_message = "rules request_headers and response_headers need an action of Append, Overwrite or Delete and a name, with a value for Append and Overwrite and none for Delete."
  }
}
