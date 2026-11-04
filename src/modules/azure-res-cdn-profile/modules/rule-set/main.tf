# =============================================================================
# FRONT DOOR RULE SET (Microsoft.Cdn/profiles/ruleSets)
# =============================================================================
# One rule set, and its rules, on an existing Front Door Standard or Premium
# profile. A rule set does nothing on its own: routes attach it by ID (an
# `afd-endpoint` route's `rule_set_resource_ids`), and one rule set can serve
# any number of routes on the profile.
#
# Front Door runs a route's rule sets in the order the route lists them, and
# each rule set's rules by ascending `order`. A rule runs its actions when all
# of its conditions match; a rule without conditions runs on every request. A
# matching rule with `stop_evaluating` skips every later rule — in this rule set
# and in every rule set after it on the route.
#
# Only the actions Front Door Standard and Premium support are exposed: route
# configuration override, request and response header changes, URL redirect
# and URL rewrite. The cache-expiration, cache-key and origin-group-override
# actions in the same ARM schema belong to Azure CDN and are left out.
#
# Rules are written one at a time (`locks` on the rule set), so parallel writes
# to one rule set never race.
# =============================================================================

locals {
  # Three conditions do not follow the DeliveryRule<name>ConditionParameters
  # pattern for their typeName.
  condition_type_names = {
    ClientPort       = "DeliveryRuleClientPortConditionParameters"
    Cookies          = "DeliveryRuleCookiesConditionParameters"
    HostName         = "DeliveryRuleHostNameConditionParameters"
    HttpVersion      = "DeliveryRuleHttpVersionConditionParameters"
    IsDevice         = "DeliveryRuleIsDeviceConditionParameters"
    PostArgs         = "DeliveryRulePostArgsConditionParameters"
    QueryString      = "DeliveryRuleQueryStringConditionParameters"
    RemoteAddress    = "DeliveryRuleRemoteAddressConditionParameters"
    RequestBody      = "DeliveryRuleRequestBodyConditionParameters"
    RequestHeader    = "DeliveryRuleRequestHeaderConditionParameters"
    RequestMethod    = "DeliveryRuleRequestMethodConditionParameters"
    RequestScheme    = "DeliveryRuleRequestSchemeConditionParameters"
    RequestUri       = "DeliveryRuleRequestUriConditionParameters"
    ServerPort       = "DeliveryRuleServerPortConditionParameters"
    SocketAddr       = "DeliveryRuleSocketAddrConditionParameters"
    SslProtocol      = "DeliveryRuleSslProtocolConditionParameters"
    UrlFileExtension = "DeliveryRuleUrlFileExtensionMatchConditionParameters"
    UrlFileName      = "DeliveryRuleUrlFilenameConditionParameters"
    UrlPath          = "DeliveryRuleUrlPathMatchConditionParameters"
  }

  # Operators each condition accepts, from the ARM schema.
  string_operators = ["Any", "Equal", "Contains", "BeginsWith", "EndsWith", "LessThan", "LessThanOrEqual", "GreaterThan", "GreaterThanOrEqual", "RegEx"]
  condition_operators = {
    ClientPort       = local.string_operators
    Cookies          = local.string_operators
    HostName         = local.string_operators
    HttpVersion      = ["Equal"]
    IsDevice         = ["Equal"]
    PostArgs         = local.string_operators
    QueryString      = local.string_operators
    RemoteAddress    = ["Any", "IPMatch", "GeoMatch"]
    RequestBody      = local.string_operators
    RequestHeader    = local.string_operators
    RequestMethod    = ["Equal"]
    RequestScheme    = ["Equal"]
    RequestUri       = local.string_operators
    ServerPort       = local.string_operators
    SocketAddr       = ["Any", "IPMatch"]
    SslProtocol      = ["Equal"]
    UrlFileExtension = local.string_operators
    UrlFileName      = local.string_operators
    UrlPath          = concat(local.string_operators, ["Wildcard"])
  }

  # Only these conditions carry a `selector` (the header, cookie or form field
  # to read); the others reject the property.
  selector_conditions = ["Cookies", "PostArgs", "RequestHeader"]
}

# -----------------------------------------------------------------------------
# Rule set
# -----------------------------------------------------------------------------

resource "azapi_resource" "this" {
  name      = var.name
  parent_id = var.cdn_profile_resource_id
  type      = "Microsoft.Cdn/profiles/ruleSets@2025-12-01"
  body      = {}
}

# -----------------------------------------------------------------------------
# Rules
# -----------------------------------------------------------------------------
# Actions are sent in a fixed sequence: route configuration override, URL
# rewrite, URL redirect, then request and response headers in list order.
#
# A route configuration override without `cache` turns caching OFF for the
# requests it matches; one without `origin_group` keeps the route's.

resource "azapi_resource" "rule" {
  for_each = var.rules

  name      = each.key
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Cdn/profiles/ruleSets/rules@2025-12-01"
  body = {
    properties = {
      order                   = each.value.order
      matchProcessingBehavior = each.value.stop_evaluating ? "Stop" : "Continue"

      conditions = [
        for condition in each.value.conditions : {
          name = condition.match_variable
          parameters = merge(
            {
              matchValues     = condition.match_values
              negateCondition = condition.negate
              operator        = condition.operator
              transforms      = condition.transforms
              typeName        = local.condition_type_names[condition.match_variable]
            },
            { for key, value in { selector = condition.selector } : key => value if value != null },
          )
        }
      ]

      actions = concat(
        each.value.route_configuration_override == null ? [] : [
          {
            name = "RouteConfigurationOverride"
            parameters = {
              cacheConfiguration = each.value.route_configuration_override.cache == null ? null : {
                cacheBehavior = coalesce(
                  each.value.route_configuration_override.cache.behavior,
                  each.value.route_configuration_override.cache.duration == null ? "HonorOrigin" : "OverrideAlways",
                )
                cacheDuration              = each.value.route_configuration_override.cache.duration
                isCompressionEnabled       = each.value.route_configuration_override.cache.compression_enabled ? "Enabled" : "Disabled"
                queryParameters            = each.value.route_configuration_override.cache.query_parameters
                queryStringCachingBehavior = each.value.route_configuration_override.cache.query_string_caching_behavior
              }
              originGroupOverride = each.value.route_configuration_override.origin_group == null ? null : {
                forwardingProtocol = each.value.route_configuration_override.origin_group.forwarding_protocol
                originGroup = {
                  id = each.value.route_configuration_override.origin_group.resource_id
                }
              }
              typeName = "DeliveryRuleRouteConfigurationOverrideActionParameters"
            }
          },
        ],
        each.value.url_rewrite == null ? [] : [
          {
            name = "UrlRewrite"
            parameters = {
              destination           = each.value.url_rewrite.destination
              preserveUnmatchedPath = each.value.url_rewrite.preserve_unmatched_path
              sourcePattern         = each.value.url_rewrite.source_pattern
              typeName              = "DeliveryRuleUrlRewriteActionParameters"
            }
          },
        ],
        each.value.url_redirect == null ? [] : [
          {
            name = "UrlRedirect"
            parameters = {
              customFragment      = each.value.url_redirect.fragment
              customHostname      = each.value.url_redirect.host_name
              customPath          = each.value.url_redirect.path
              customQueryString   = each.value.url_redirect.query_string
              destinationProtocol = each.value.url_redirect.protocol
              redirectType        = each.value.url_redirect.redirect_type
              typeName            = "DeliveryRuleUrlRedirectActionParameters"
            }
          },
        ],
        [
          for header in each.value.request_headers : {
            name = "ModifyRequestHeader"
            parameters = merge(
              {
                headerAction = header.action
                headerName   = header.name
                typeName     = "DeliveryRuleHeaderActionParameters"
              },
              { for key, value in { value = header.value } : key => value if value != null },
            )
          }
        ],
        [
          for header in each.value.response_headers : {
            name = "ModifyResponseHeader"
            parameters = merge(
              {
                headerAction = header.action
                headerName   = header.name
                typeName     = "DeliveryRuleHeaderActionParameters"
              },
              { for key, value in { value = header.value } : key => value if value != null },
            )
          }
        ],
      )
    }
  }
  locks = [azapi_resource.this.id]
}
