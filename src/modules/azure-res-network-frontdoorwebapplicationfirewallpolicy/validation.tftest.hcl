# =============================================================================
# azure-res-network-frontdoorwebapplicationfirewallpolicy tests
# =============================================================================
# `mock_provider` keeps the suite offline: negative runs abort during variable
# validation, and the positive runs need a resource graph but not a real
# subscription.
#
# Caveat: mocking bypasses AzAPI's own schema checks, so the positive runs cannot
# confirm ARM accepts a body. The variable validation blocks are the guard.
# =============================================================================

mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }

  mock_data "azapi_resource_list" {
    defaults = {
      output = {
        results = [
          {
            id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
            role_name = "Reader"
          },
        ]
      }
    }
  }
}

mock_provider "random" {}

variables {
  name                = "wafexample"
  resource_group_name = "rg-example"
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans_a_standard_policy_with_defaults" {
  command = plan

  assert {
    condition     = azapi_resource.this.location == "global" && azapi_resource.this.body.sku.name == "Standard_AzureFrontDoor"
    error_message = "the policy must be global and default to the Standard tier"
  }
  assert {
    condition = (
      azapi_resource.this.body.properties.policySettings.enabledState == "Enabled" &&
      azapi_resource.this.body.properties.policySettings.mode == "Prevention" &&
      azapi_resource.this.body.properties.policySettings.requestBodyCheck == "Enabled"
    )
    error_message = "the policy must default to enabled, Prevention, with body inspection"
  }
  assert {
    condition = alltrue([
      for key in ["redirectUrl", "customBlockResponseStatusCode", "customBlockResponseBody", "captchaExpirationInMinutes", "javascriptChallengeExpirationInMinutes", "logScrubbing"] :
      !contains(keys(azapi_resource.this.body.properties.policySettings), key)
    ])
    error_message = "unset optional settings must be left out of the body"
  }
  assert {
    condition = (
      length(azapi_resource.this.body.properties.customRules.rules) == 0 &&
      length(azapi_resource.this.body.properties.managedRules.managedRuleSets) == 0
    )
    error_message = "a policy with no rules must send empty rule lists"
  }
}

run "plans_listing_block_and_rate_limit_rules" {
  command = plan

  variables {
    custom_rules = {
      BlockContainerListing = {
        priority = 10
        action   = "Block"
        match_conditions = [
          {
            match_variable = "QueryString"
            operator       = "Contains"
            match_values   = ["comp=list", "restype=container"]
            transforms     = ["Lowercase", "UrlDecode"]
          },
        ]
      }
      RateLimitPerClient = {
        priority             = 20
        action               = "Block"
        rule_type            = "RateLimitRule"
        rate_limit_threshold = 300
        group_by             = ["SocketAddr"]
        match_conditions = [
          {
            match_variable = "RequestUri"
            operator       = "Any"
            match_values   = []
          },
        ]
      }
    }
  }

  assert {
    condition = (
      azapi_resource.this.body.properties.customRules.rules[0].name == "BlockContainerListing" &&
      azapi_resource.this.body.properties.customRules.rules[0].matchConditions[0].transforms == tolist(["Lowercase", "UrlDecode"]) &&
      !contains(keys(azapi_resource.this.body.properties.customRules.rules[0].matchConditions[0]), "selector")
    )
    error_message = "a match rule must carry its condition, with an unset selector left out"
  }
  assert {
    condition     = !contains(keys(azapi_resource.this.body.properties.customRules.rules[0]), "rateLimitThreshold")
    error_message = "a match rule must not send rate-limit settings"
  }
  assert {
    condition = (
      azapi_resource.this.body.properties.customRules.rules[1].rateLimitThreshold == 300 &&
      azapi_resource.this.body.properties.customRules.rules[1].rateLimitDurationInMinutes == 1 &&
      azapi_resource.this.body.properties.customRules.rules[1].groupBy[0].variableName == "SocketAddr"
    )
    error_message = "a rate-limit rule must send its threshold, window and grouping"
  }
}

run "plans_premium_managed_rule_sets_with_an_override" {
  command = plan

  variables {
    sku = "Premium_AzureFrontDoor"
    managed_rule_sets = [
      {
        type    = "Microsoft_DefaultRuleSet"
        version = "2.1"
        action  = "Block"
        rule_group_overrides = {
          SQLI = {
            rules = {
              "942440" = {
                action = "AnomalyScoring"
                exclusions = [
                  {
                    match_variable          = "RequestCookieNames"
                    selector                = "session"
                    selector_match_operator = "Equals"
                  },
                ]
              }
            }
          }
        }
      },
      {
        type    = "Microsoft_BotManagerRuleSet"
        version = "1.1"
      },
    ]
  }

  assert {
    condition = (
      azapi_resource.this.body.properties.managedRules.managedRuleSets[0].ruleSetAction == "Block" &&
      azapi_resource.this.body.properties.managedRules.managedRuleSets[0].ruleGroupOverrides[0].ruleGroupName == "SQLI" &&
      azapi_resource.this.body.properties.managedRules.managedRuleSets[0].ruleGroupOverrides[0].rules[0].ruleId == "942440" &&
      azapi_resource.this.body.properties.managedRules.managedRuleSets[0].ruleGroupOverrides[0].rules[0].action == "AnomalyScoring"
    )
    error_message = "the Default Rule Set must carry its action and the override"
  }
  assert {
    condition     = !contains(keys(azapi_resource.this.body.properties.managedRules.managedRuleSets[1]), "ruleSetAction")
    error_message = "a rule set without an action must leave ruleSetAction out"
  }
}

# =============================================================================
# NEGATIVE — variable validation
# =============================================================================

run "rejects_managed_rule_sets_on_standard" {
  command = plan

  variables {
    managed_rule_sets = [
      {
        type    = "Microsoft_DefaultRuleSet"
        version = "2.1"
        action  = "Block"
      },
    ]
  }

  expect_failures = [var.managed_rule_sets]
}

run "rejects_a_name_with_a_hyphen" {
  command = plan

  variables {
    name = "waf-example"
  }

  expect_failures = [var.name]
}

run "rejects_duplicate_custom_rule_priorities" {
  command = plan

  variables {
    custom_rules = {
      One = {
        priority         = 10
        action           = "Block"
        match_conditions = [{ match_variable = "RequestMethod", operator = "Equal", match_values = ["DELETE"] }]
      }
      Two = {
        priority         = 10
        action           = "Block"
        match_conditions = [{ match_variable = "RequestMethod", operator = "Equal", match_values = ["PUT"] }]
      }
    }
  }

  expect_failures = [var.custom_rules]
}

run "rejects_a_rate_limit_rule_without_a_threshold" {
  command = plan

  variables {
    custom_rules = {
      RateLimit = {
        priority         = 10
        action           = "Block"
        rule_type        = "RateLimitRule"
        match_conditions = [{ match_variable = "RequestUri", operator = "Any", match_values = [] }]
      }
    }
  }

  expect_failures = [var.custom_rules]
}

run "rejects_a_body_that_is_not_base64" {
  command = plan

  variables {
    policy_settings = {
      custom_block_response_body = "<html>blocked</html>"
    }
  }

  expect_failures = [var.policy_settings]
}

run "rejects_an_unknown_match_variable" {
  command = plan

  variables {
    custom_rules = {
      Bad = {
        priority         = 10
        action           = "Block"
        match_conditions = [{ match_variable = "RequestPath", operator = "Contains", match_values = ["x"] }]
      }
    }
  }

  expect_failures = [var.custom_rules]
}
