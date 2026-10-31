# =============================================================================
# azure-res-network-applicationgatewaywebapplicationfirewallpolicy tests
# =============================================================================
# `mock_provider` keeps the suite offline: negative runs abort during variable
# validation, and the positive runs need a resource graph but not a real
# subscription.
#
# The positive runs are the ones that construct the resource graph and evaluate
# the outputs — an `expect_failures`-only suite never does, so a bad attribute
# reference would pass it green.
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

  # A valid ARM ID, because an apply run leaves this policy in the shared test
  # state and a later run parents role assignments on it.
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/applicationGatewayWebApplicationFirewallPolicies/waf-example"
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
  name                = "waf-example"
  resource_group_name = "rg-example"
  location            = "westeurope"

  managed_rules = {
    managed_rule_sets = [
      {
        version = "2.1"
        rule_group_overrides = {
          SQLI = {
            rules = {
              "942440" = { action = "Log" }
              "942200" = { enabled = true }
            }
          }
          General = {
            rules = {
              "200002" = { action = "Log" }
            }
          }
        }
      },
      {
        type    = "Microsoft_BotManagerRuleSet"
        version = "1.1"
      },
    ]
    exclusions = [
      {
        match_variable          = "RequestArgNames"
        selector                = "Address"
        selector_match_operator = "Equals"
        excluded_rule_set = {
          rule_groups = [
            { rule_group_name = "SQLI", excluded_rules = ["942110"] },
            { rule_group_name = "RCE" },
          ]
        }
      },
      {
        match_variable          = "RequestCookieNames"
        selector                = "session"
        selector_match_operator = "StartsWith"
      },
    ]
  }
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "defaults_and_managed_rules" {
  command = plan

  assert {
    condition     = azapi_resource.this.type == "Microsoft.Network/applicationGatewayWebApplicationFirewallPolicies@2025-07-01"
    error_message = "The type must use ARM's lowercase-a spelling, so resource IDs match what ARM hands out."
  }

  assert {
    condition = azapi_resource.this.body.properties.policySettings == {
      fileUploadEnforcement             = true
      fileUploadLimitInMb               = 100
      jsChallengeCookieExpirationInMins = 30
      maxRequestBodySizeInKb            = 128
      mode                              = "Prevention"
      requestBodyCheck                  = true
      requestBodyEnforcement            = true
      requestBodyInspectLimitInKB       = 128
      state                             = "Enabled"
    }
    error_message = "Default policy settings must be Azure's defaults, with no logScrubbing key."
  }

  assert {
    condition     = azapi_resource.this.body.properties.customRules == []
    error_message = "No custom rules must send an empty list."
  }

  # Override groups and rules follow map-key order; an override without
  # `enabled` is Disabled, and `action` is only present when set.
  assert {
    condition = azapi_resource.this.body.properties.managedRules.managedRuleSets[0] == {
      ruleGroupOverrides = [
        {
          ruleGroupName = "General"
          rules         = [{ action = "Log", ruleId = "200002", state = "Disabled" }]
        },
        {
          ruleGroupName = "SQLI"
          rules = [
            { ruleId = "942200", state = "Enabled" },
            { action = "Log", ruleId = "942440", state = "Disabled" },
          ]
        },
      ]
      ruleSetType    = "Microsoft_DefaultRuleSet"
      ruleSetVersion = "2.1"
    }
    error_message = "The DRS rule set body does not match the expected overrides."
  }

  assert {
    condition = azapi_resource.this.body.properties.managedRules.managedRuleSets[1] == {
      ruleGroupOverrides = []
      ruleSetType        = "Microsoft_BotManagerRuleSet"
      ruleSetVersion     = "1.1"
    }
    error_message = "A rule set without overrides must send an empty override list."
  }

  # Exclusion rule groups keep list order; a group without rules sends an empty
  # list; an exclusion without a rule set sends no rule sets.
  assert {
    condition = azapi_resource.this.body.properties.managedRules.exclusions == [
      {
        exclusionManagedRuleSets = [
          {
            ruleGroups = [
              { ruleGroupName = "SQLI", rules = [{ ruleId = "942110" }] },
              { ruleGroupName = "RCE", rules = [] },
            ]
            ruleSetType    = "Microsoft_DefaultRuleSet"
            ruleSetVersion = "2.1"
          },
        ]
        matchVariable         = "RequestArgNames"
        selector              = "Address"
        selectorMatchOperator = "Equals"
      },
      {
        exclusionManagedRuleSets = []
        matchVariable            = "RequestCookieNames"
        selector                 = "session"
        selectorMatchOperator    = "StartsWith"
      },
    ]
    error_message = "The exclusions body does not match the expected shape."
  }

  assert {
    condition     = output.resource_group_name == "rg-example" && output.role_assignments == {}
    error_message = "Outputs must evaluate."
  }
}

run "custom_rules_and_log_scrubbing" {
  command = plan

  variables {
    policy_settings = {
      mode                        = "Detection"
      max_request_body_size_in_kb = 2000
      log_scrubbing = {
        rules = [
          { match_variable = "RequestHeaderNames", selector = "Authorization" },
          { match_variable = "RequestIPAddress", selector_match_operator = "EqualsAny", enabled = false },
        ]
      }
    }

    custom_rules = {
      BlockAdmin = {
        priority = 10
        action   = "Block"
        match_conditions = [
          {
            match_variables = [{ variable_name = "RequestUri" }]
            operator        = "Regex"
            match_values    = ["^/admin"]
            transforms      = ["UrlDecode", "Lowercase"]
          },
          {
            match_variables    = [{ variable_name = "RequestHeaders", selector = "Host" }]
            operator           = "Equal"
            negation_condition = true
            match_values       = ["admin.example.com"]
          },
        ]
      }
      AThrottleLogin = {
        priority             = 20
        action               = "Block"
        rule_type            = "RateLimitRule"
        rate_limit_duration  = "OneMin"
        rate_limit_threshold = 100
        group_rate_limit_by  = "ClientAddr"
        enabled              = false
        match_conditions = [
          {
            match_variables = [{ variable_name = "RequestUri" }]
            operator        = "Contains"
            match_values    = ["/login"]
          },
        ]
      }
    }
  }

  assert {
    condition = azapi_resource.this.body.properties.policySettings.logScrubbing == {
      scrubbingRules = [
        { matchVariable = "RequestHeaderNames", selector = "Authorization", selectorMatchOperator = "Equals", state = "Enabled" },
        { matchVariable = "RequestIPAddress", selectorMatchOperator = "EqualsAny", state = "Disabled" },
      ]
      state = "Enabled"
    }
    error_message = "Log scrubbing must send rules in order, omitting an unset selector."
  }

  assert {
    condition     = azapi_resource.this.body.properties.policySettings.mode == "Detection" && azapi_resource.this.body.properties.policySettings.maxRequestBodySizeInKb == 2000
    error_message = "Overridden policy settings must reach the body."
  }

  # Map-key order: AThrottleLogin sorts before BlockAdmin. Compared as JSON: the
  # body holds lists where the literal holds tuples.
  assert {
    condition = jsonencode(azapi_resource.this.body.properties.customRules[0]) == jsonencode({
      action             = "Block"
      groupByUserSession = [{ groupByVariables = [{ variableName = "ClientAddr" }] }]
      matchConditions = [
        {
          matchValues      = ["/login"]
          matchVariables   = [{ variableName = "RequestUri" }]
          negationConditon = false
          operator         = "Contains"
          transforms       = []
        },
      ]
      name               = "AThrottleLogin"
      priority           = 20
      rateLimitDuration  = "OneMin"
      rateLimitThreshold = 100
      ruleType           = "RateLimitRule"
      state              = "Disabled"
    })
    error_message = "The rate-limit rule body does not match the expected shape."
  }

  assert {
    condition = jsonencode(azapi_resource.this.body.properties.customRules[1]) == jsonencode({
      action = "Block"
      matchConditions = [
        {
          matchValues      = ["^/admin"]
          matchVariables   = [{ variableName = "RequestUri" }]
          negationConditon = false
          operator         = "Regex"
          transforms       = ["UrlDecode", "Lowercase"]
        },
        {
          matchValues      = ["admin.example.com"]
          matchVariables   = [{ selector = "Host", variableName = "RequestHeaders" }]
          negationConditon = true
          operator         = "Equal"
          transforms       = []
        },
      ]
      name     = "BlockAdmin"
      priority = 10
      ruleType = "MatchRule"
      state    = "Enabled"
    })
    error_message = "A match rule must carry no rate-limit keys and omit an unset selector."
  }
}

run "role_assignments" {
  command = apply

  variables {
    role_assignments = {
      reader = {
        role_definition_id_or_name = "Reader"
        principal_id               = "11111111-1111-1111-1111-111111111111"
        principal_type             = "ServicePrincipal"
      }
    }
  }

  assert {
    condition     = azapi_resource.role_assignments["reader"].body.properties.roleDefinitionId == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
    error_message = "A role name must resolve to its definition ID."
  }

  assert {
    condition     = output.role_assignments["reader"].principal_id == "11111111-1111-1111-1111-111111111111"
    error_message = "The role_assignments output must carry the principal."
  }
}

# =============================================================================
# NEGATIVE — variable validation
# =============================================================================

run "rejects_bad_name" {
  command = plan
  variables {
    name = "-waf"
  }
  expect_failures = [var.name]
}

run "rejects_resource_group_id" {
  command = plan
  variables {
    resource_group_name = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"
  }
  expect_failures = [var.resource_group_name]
}

run "rejects_bad_mode" {
  command = plan
  variables {
    policy_settings = { mode = "Block" }
  }
  expect_failures = [var.policy_settings]
}

run "rejects_scrubbing_equals_without_selector" {
  command = plan
  variables {
    policy_settings = {
      log_scrubbing = { rules = [{ match_variable = "RequestHeaderNames" }] }
    }
  }
  expect_failures = [var.policy_settings]
}

run "rejects_empty_override_group" {
  command = plan
  variables {
    managed_rules = {
      managed_rule_sets = [{ version = "2.1", rule_group_overrides = { SQLI = { rules = {} } } }]
    }
  }
  expect_failures = [var.managed_rules]
}

run "rejects_duplicate_rule_set_type" {
  command = plan
  variables {
    managed_rules = {
      managed_rule_sets = [{ version = "2.1" }, { version = "2.2" }]
    }
  }
  expect_failures = [var.managed_rules]
}

run "rejects_bad_override_action" {
  command = plan
  variables {
    managed_rules = {
      managed_rule_sets = [{ version = "2.1", rule_group_overrides = { SQLI = { rules = { "942440" = { action = "Deny" } } } } }]
    }
  }
  expect_failures = [var.managed_rules]
}

run "rejects_bad_exclusion_match_variable" {
  command = plan
  variables {
    managed_rules = {
      managed_rule_sets = [{ version = "2.1" }]
      exclusions        = [{ match_variable = "RequestUri", selector = "x", selector_match_operator = "Equals" }]
    }
  }
  expect_failures = [var.managed_rules]
}

run "rejects_duplicate_priority" {
  command = plan
  variables {
    custom_rules = {
      One = { priority = 10, action = "Block", match_conditions = [{ match_variables = [{ variable_name = "RequestUri" }], operator = "Contains", match_values = ["/a"] }] }
      Two = { priority = 10, action = "Block", match_conditions = [{ match_variables = [{ variable_name = "RequestUri" }], operator = "Contains", match_values = ["/b"] }] }
    }
  }
  expect_failures = [var.custom_rules]
}

run "rejects_priority_out_of_range" {
  command = plan
  variables {
    custom_rules = {
      One = { priority = 101, action = "Block", match_conditions = [{ match_variables = [{ variable_name = "RequestUri" }], operator = "Contains", match_values = ["/a"] }] }
    }
  }
  expect_failures = [var.custom_rules]
}

run "rejects_rate_limit_without_threshold" {
  command = plan
  variables {
    custom_rules = {
      One = { priority = 1, action = "Block", rule_type = "RateLimitRule", rate_limit_duration = "OneMin", match_conditions = [{ match_variables = [{ variable_name = "RequestUri" }], operator = "Contains", match_values = ["/a"] }] }
    }
  }
  expect_failures = [var.custom_rules]
}

run "rejects_rate_limit_settings_on_match_rule" {
  command = plan
  variables {
    custom_rules = {
      One = { priority = 1, action = "Block", rate_limit_threshold = 10, match_conditions = [{ match_variables = [{ variable_name = "RequestUri" }], operator = "Contains", match_values = ["/a"] }] }
    }
  }
  expect_failures = [var.custom_rules]
}

run "rejects_condition_without_values" {
  command = plan
  variables {
    custom_rules = {
      One = { priority = 1, action = "Block", match_conditions = [{ match_variables = [{ variable_name = "RequestUri" }], operator = "Regex" }] }
    }
  }
  expect_failures = [var.custom_rules]
}

run "rejects_bad_transform" {
  command = plan
  variables {
    custom_rules = {
      One = { priority = 1, action = "Block", match_conditions = [{ match_variables = [{ variable_name = "RequestUri" }], operator = "Contains", match_values = ["/a"], transforms = ["Base64Decode"] }] }
    }
  }
  expect_failures = [var.custom_rules]
}

run "rejects_bad_role_assignment_name" {
  command = plan
  variables {
    role_assignments = {
      reader = {
        name                       = "not-a-guid"
        role_definition_id_or_name = "Reader"
        principal_id               = "11111111-1111-1111-1111-111111111111"
      }
    }
  }
  expect_failures = [var.role_assignments]
}
