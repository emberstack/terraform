# =============================================================================
# azure-res-cdn-profile/modules/rule-set tests
# =============================================================================
# `mock_provider` keeps the suite offline: negative runs abort during variable
# validation, and the positive runs need a resource graph but not a real
# subscription.
#
# Caveat: mocking bypasses AzAPI's own schema checks, so the positive runs cannot
# confirm ARM accepts a body. The variable validation blocks are the guard.
# =============================================================================

mock_provider "azapi" {}

variables {
  cdn_profile_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Cdn/profiles/afd-example"
  name                    = "securityheaders"
  rules = {
    hsts = {
      order = 0
      response_headers = [
        {
          action = "Overwrite"
          name   = "Strict-Transport-Security"
          value  = "max-age=31536000"
        },
        {
          action = "Delete"
          name   = "Server"
        },
      ]
    }
  }
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans_an_unconditional_header_rule" {
  command = plan

  assert {
    condition = (
      azapi_resource.this.name == "securityheaders" &&
      azapi_resource.this.parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Cdn/profiles/afd-example"
    )
    error_message = "the rule set must be a profile child carrying the given name"
  }
  assert {
    condition = (
      azapi_resource.rule["hsts"].body.properties.order == 0 &&
      length(azapi_resource.rule["hsts"].body.properties.conditions) == 0 &&
      azapi_resource.rule["hsts"].body.properties.matchProcessingBehavior == "Continue"
    )
    error_message = "a rule without conditions must send an empty list and continue by default"
  }
  assert {
    condition = (
      azapi_resource.rule["hsts"].body.properties.actions[0].name == "ModifyResponseHeader" &&
      azapi_resource.rule["hsts"].body.properties.actions[0].parameters.typeName == "DeliveryRuleHeaderActionParameters" &&
      azapi_resource.rule["hsts"].body.properties.actions[0].parameters.value == "max-age=31536000"
    )
    error_message = "a response header change must be a ModifyResponseHeader action carrying its value"
  }
  assert {
    condition     = !can(azapi_resource.rule["hsts"].body.properties.actions[1].parameters.value)
    error_message = "a Delete header action must not send a value"
  }
}

run "plans_conditions_with_their_type_names_and_selectors" {
  command = plan

  variables {
    rules = {
      oldpaths = {
        order           = 1
        stop_evaluating = true
        conditions = [
          {
            match_variable = "UrlPath"
            operator       = "BeginsWith"
            match_values   = ["legacy/"]
            transforms     = ["Lowercase"]
          },
          {
            match_variable = "UrlFileName"
            operator       = "Equal"
            match_values   = ["index.html"]
          },
          {
            match_variable = "UrlFileExtension"
            operator       = "Equal"
            match_values   = ["html"]
          },
          {
            match_variable = "RequestHeader"
            selector       = "X-Kiosk"
            operator       = "Any"
            negate         = true
          },
        ]
        response_headers = [{ action = "Append", name = "X-Legacy", value = "1" }]
      }
    }
  }

  assert {
    condition = (
      azapi_resource.rule["oldpaths"].body.properties.conditions[0].parameters.typeName == "DeliveryRuleUrlPathMatchConditionParameters" &&
      azapi_resource.rule["oldpaths"].body.properties.conditions[1].parameters.typeName == "DeliveryRuleUrlFilenameConditionParameters" &&
      azapi_resource.rule["oldpaths"].body.properties.conditions[2].parameters.typeName == "DeliveryRuleUrlFileExtensionMatchConditionParameters" &&
      azapi_resource.rule["oldpaths"].body.properties.conditions[3].parameters.typeName == "DeliveryRuleRequestHeaderConditionParameters"
    )
    error_message = "each condition must carry its ARM typeName, including the three that break the naming pattern"
  }
  assert {
    condition = (
      azapi_resource.rule["oldpaths"].body.properties.conditions[3].parameters.selector == "X-Kiosk" &&
      azapi_resource.rule["oldpaths"].body.properties.conditions[3].parameters.negateCondition == true &&
      !can(azapi_resource.rule["oldpaths"].body.properties.conditions[0].parameters.selector)
    )
    error_message = "only a header, cookie or form field condition may send a selector"
  }
  assert {
    condition     = azapi_resource.rule["oldpaths"].body.properties.matchProcessingBehavior == "Stop"
    error_message = "stop_evaluating must send Stop"
  }
}

run "plans_route_configuration_overrides" {
  command = plan

  variables {
    rules = {
      fixedttl = {
        order = 1
        route_configuration_override = {
          cache = { duration = "0.06:00:00" }
        }
      }
      honororigin = {
        order = 2
        route_configuration_override = {
          cache = {
            query_string_caching_behavior = "IncludeSpecifiedQueryStrings"
            query_parameters              = "version"
          }
        }
      }
      nocache = {
        order = 3
        conditions = [
          { match_variable = "UrlPath", operator = "BeginsWith", match_values = ["api/"] },
        ]
        route_configuration_override = {
          origin_group = {
            resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Cdn/profiles/afd-example/originGroups/og-api"
          }
        }
      }
    }
  }

  assert {
    condition = (
      azapi_resource.rule["fixedttl"].body.properties.actions[0].name == "RouteConfigurationOverride" &&
      azapi_resource.rule["fixedttl"].body.properties.actions[0].parameters.cacheConfiguration.cacheBehavior == "OverrideAlways" &&
      azapi_resource.rule["fixedttl"].body.properties.actions[0].parameters.cacheConfiguration.cacheDuration == "0.06:00:00" &&
      azapi_resource.rule["fixedttl"].body.properties.actions[0].parameters.originGroupOverride == null
    )
    error_message = "a duration without a behavior must override always, keeping the route's origin group"
  }
  assert {
    condition = (
      azapi_resource.rule["honororigin"].body.properties.actions[0].parameters.cacheConfiguration.cacheBehavior == "HonorOrigin" &&
      azapi_resource.rule["honororigin"].body.properties.actions[0].parameters.cacheConfiguration.cacheDuration == null &&
      azapi_resource.rule["honororigin"].body.properties.actions[0].parameters.cacheConfiguration.queryParameters == "version"
    )
    error_message = "a cache block without a duration must honor the origin"
  }
  assert {
    condition = (
      azapi_resource.rule["nocache"].body.properties.actions[0].parameters.cacheConfiguration == null &&
      azapi_resource.rule["nocache"].body.properties.actions[0].parameters.originGroupOverride.forwardingProtocol == "HttpsOnly" &&
      endswith(azapi_resource.rule["nocache"].body.properties.actions[0].parameters.originGroupOverride.originGroup.id, "/originGroups/og-api")
    )
    error_message = "an origin group override without cache must send caching as null and forward HTTPS only by default"
  }
}

run "plans_a_rewrite_and_a_redirect" {
  command = plan

  variables {
    rules = {
      rewrite = {
        order       = 1
        url_rewrite = { source_pattern = "/v1/", destination = "/maintenance/" }
      }
      redirect = {
        order = 2
        conditions = [
          { match_variable = "RequestScheme", operator = "Equal", match_values = ["HTTP"] },
        ]
        url_redirect = { redirect_type = "PermanentRedirect", protocol = "Https" }
      }
    }
  }

  assert {
    condition = (
      azapi_resource.rule["rewrite"].body.properties.actions[0].name == "UrlRewrite" &&
      azapi_resource.rule["rewrite"].body.properties.actions[0].parameters.preserveUnmatchedPath == true &&
      azapi_resource.rule["rewrite"].body.properties.actions[0].parameters.destination == "/maintenance/"
    )
    error_message = "a rewrite must keep the unmatched path by default"
  }
  assert {
    condition = (
      azapi_resource.rule["redirect"].body.properties.actions[0].name == "UrlRedirect" &&
      azapi_resource.rule["redirect"].body.properties.actions[0].parameters.redirectType == "PermanentRedirect" &&
      azapi_resource.rule["redirect"].body.properties.actions[0].parameters.destinationProtocol == "Https" &&
      azapi_resource.rule["redirect"].body.properties.actions[0].parameters.customPath == null
    )
    error_message = "a redirect must carry its type and protocol, leaving unset URL parts null"
  }
}

# =============================================================================
# NEGATIVE — variable validation
# =============================================================================

run "rejects_a_hyphenated_rule_set_name" {
  command = plan

  variables {
    name = "security-headers"
  }

  expect_failures = [var.name]
}

run "rejects_a_hyphenated_rule_name" {
  command = plan

  variables {
    rules = {
      "no-cache" = {
        order            = 0
        response_headers = [{ action = "Overwrite", name = "Cache-Control", value = "no-store" }]
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_duplicate_orders" {
  command = plan

  variables {
    rules = {
      first = {
        order            = 1
        response_headers = [{ action = "Delete", name = "Server" }]
      }
      second = {
        order            = 1
        response_headers = [{ action = "Delete", name = "X-Powered-By" }]
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_an_unknown_match_variable" {
  command = plan

  variables {
    rules = {
      geo = {
        order            = 1
        conditions       = [{ match_variable = "Country", operator = "Equal", match_values = ["RO"] }]
        response_headers = [{ action = "Delete", name = "Server" }]
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_an_operator_the_condition_does_not_take" {
  command = plan

  variables {
    rules = {
      office = {
        order            = 1
        conditions       = [{ match_variable = "RemoteAddress", operator = "Equal", match_values = ["10.0.0.0/8"] }]
        response_headers = [{ action = "Delete", name = "Server" }]
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_a_header_condition_without_a_selector" {
  command = plan

  variables {
    rules = {
      kiosk = {
        order            = 1
        conditions       = [{ match_variable = "RequestHeader", operator = "Equal", match_values = ["1"] }]
        response_headers = [{ action = "Delete", name = "Server" }]
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_a_selector_on_a_path_condition" {
  command = plan

  variables {
    rules = {
      paths = {
        order            = 1
        conditions       = [{ match_variable = "UrlPath", selector = "X-Kiosk", operator = "BeginsWith", match_values = ["a/"] }]
        response_headers = [{ action = "Delete", name = "Server" }]
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_a_condition_without_match_values" {
  command = plan

  variables {
    rules = {
      paths = {
        order            = 1
        conditions       = [{ match_variable = "UrlPath", operator = "BeginsWith" }]
        response_headers = [{ action = "Delete", name = "Server" }]
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_an_unknown_request_method" {
  command = plan

  variables {
    rules = {
      methods = {
        order            = 1
        conditions       = [{ match_variable = "RequestMethod", operator = "Equal", match_values = ["PATCH"] }]
        response_headers = [{ action = "Delete", name = "Server" }]
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_a_rule_without_actions" {
  command = plan

  variables {
    rules = {
      empty = {
        order = 1
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_more_than_five_actions" {
  command = plan

  variables {
    rules = {
      busy = {
        order = 1
        response_headers = [
          { action = "Delete", name = "Server" },
          { action = "Delete", name = "X-Powered-By" },
          { action = "Delete", name = "X-AspNet-Version" },
          { action = "Delete", name = "X-Cache-Info" },
          { action = "Delete", name = "X-Azure-Ref" },
          { action = "Delete", name = "Via" },
        ]
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_a_redirect_with_a_rewrite" {
  command = plan

  variables {
    rules = {
      both = {
        order        = 1
        url_rewrite  = { source_pattern = "/a/", destination = "/b/" }
        url_redirect = { path = "/c/" }
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_a_duration_while_honoring_the_origin" {
  command = plan

  variables {
    rules = {
      ttl = {
        order = 1
        route_configuration_override = {
          cache = {
            behavior = "HonorOrigin"
            duration = "00:01:00"
          }
        }
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_an_override_without_a_duration" {
  command = plan

  variables {
    rules = {
      ttl = {
        order = 1
        route_configuration_override = {
          cache = { behavior = "OverrideIfOriginMissing" }
        }
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_a_malformed_cache_duration" {
  command = plan

  variables {
    rules = {
      ttl = {
        order = 1
        route_configuration_override = {
          cache = { duration = "60s" }
        }
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_a_delete_header_with_a_value" {
  command = plan

  variables {
    rules = {
      strip = {
        order            = 1
        response_headers = [{ action = "Delete", name = "Server", value = "x" }]
      }
    }
  }

  expect_failures = [var.rules]
}

run "rejects_a_rewrite_without_a_leading_slash" {
  command = plan

  variables {
    rules = {
      rewrite = {
        order       = 1
        url_rewrite = { source_pattern = "v1/", destination = "/maintenance/" }
      }
    }
  }

  expect_failures = [var.rules]
}
