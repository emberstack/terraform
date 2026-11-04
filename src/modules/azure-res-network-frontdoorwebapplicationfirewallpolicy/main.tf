# =============================================================================
# FRONT DOOR WAF POLICY
# (Microsoft.Network/frontDoorWebApplicationFirewallPolicies)
# =============================================================================
# A WAF policy for Front Door Standard or Premium: policy settings, custom and
# rate-limit rules, and managed rule sets with per-rule overrides and
# exclusions. Attaching it is the job of a Front Door security policy —
# `azure-res-cdn-profile/modules/afd-endpoint` — not this module's.
#
# The policy's SKU must match the profile it protects. Standard runs custom
# rules only; managed rule sets (the Default Rule Set, bot protection) need
# Premium, and the variables reject them on Standard.
#
# The policy is a global resource: `location` is always `global`.
#
# List order is part of the body, so it follows the inputs: custom rules in
# map-key order, overrides in map-key order, managed rule sets and exclusions
# in list order. Optional settings left unset are left out of the body rather
# than sent as null.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The input stays a plain resource group name (AVM's shape); the subscription
  # comes from the configured provider, so an aliased or multi-subscription
  # caller still lands in the right place.
  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  resource_group_resource_id        = "${local.provider_subscription_resource_id}/resourceGroups/${var.resource_group_name}"

  # Every role this module assigns, as the caller spelled it — a display name or an
  # ARM resource ID. Deduplication happens in `role_definition_resource_ids`.
  role_definition_names = [for v in values(var.role_assignments) : v.role_definition_id_or_name]

  role_definition_name_to_resource_id = length(local.role_definition_names) > 0 ? {
    for definition in data.azapi_resource_list.role_definitions[0].output.results : definition.role_name => definition.id
  } : {}

  # Keyed by role, not by assignment key: a role definition is a property of the
  # ROLE, so two assignments naming the same role share one entry. An entry that is
  # already a resource ID falls through the lookup untouched and maps to itself.
  role_definition_resource_ids = {
    for name in toset(local.role_definition_names) :
    name => lookup(local.role_definition_name_to_resource_id, name, name)
  }

  # Optional keys are added with `merge([for _ in <0 or 1 items> : {...}]...)`, which
  # is `{}` or the one object: a conditional between `{}` and an object with
  # attributes is a type error, and only a call's last argument may be expanded.
  policy_settings = merge(
    {
      enabledState     = var.policy_settings.enabled ? "Enabled" : "Disabled"
      mode             = var.policy_settings.mode
      requestBodyCheck = var.policy_settings.request_body_check_enabled ? "Enabled" : "Disabled"
    },
    merge([for v in var.policy_settings.redirect_url == null ? [] : [var.policy_settings.redirect_url] : { redirectUrl = v }]...),
    merge([for v in var.policy_settings.custom_block_response_status_code == null ? [] : [var.policy_settings.custom_block_response_status_code] : { customBlockResponseStatusCode = v }]...),
    merge([for v in var.policy_settings.custom_block_response_body == null ? [] : [var.policy_settings.custom_block_response_body] : { customBlockResponseBody = v }]...),
    merge([for v in var.policy_settings.captcha_expiration_in_minutes == null ? [] : [var.policy_settings.captcha_expiration_in_minutes] : { captchaExpirationInMinutes = v }]...),
    merge([for v in var.policy_settings.js_challenge_expiration_in_minutes == null ? [] : [var.policy_settings.js_challenge_expiration_in_minutes] : { javascriptChallengeExpirationInMinutes = v }]...),
    [
      for scrubbing in var.policy_settings.log_scrubbing == null ? [] : [var.policy_settings.log_scrubbing] : {
        logScrubbing = {
          scrubbingRules = [
            for rule in scrubbing.rules : merge(
              {
                matchVariable         = rule.match_variable
                selectorMatchOperator = rule.selector_match_operator
                state                 = rule.enabled ? "Enabled" : "Disabled"
              },
              [for selector in rule.selector == null ? [] : [rule.selector] : { selector = selector }]...
            )
          ]
          state = scrubbing.enabled ? "Enabled" : "Disabled"
        }
      }
    ]...
  )

  custom_rules = [
    for name, rule in var.custom_rules : merge(
      {
        action       = rule.action
        enabledState = rule.enabled ? "Enabled" : "Disabled"
        matchConditions = [
          for condition in rule.match_conditions : merge(
            {
              matchValue      = condition.match_values
              matchVariable   = condition.match_variable
              negateCondition = condition.negate
              operator        = condition.operator
              transforms      = condition.transforms
            },
            [for selector in condition.selector == null ? [] : [condition.selector] : { selector = selector }]...
          )
        ]
        name     = name
        priority = rule.priority
        ruleType = rule.rule_type
      },
      # Rate-limit settings belong to rate-limit rules only; on a match rule ARM
      # ignores them, so they are not sent.
      [
        for _ in rule.rule_type == "RateLimitRule" ? [rule] : [] : merge(
          {
            rateLimitDurationInMinutes = rule.rate_limit_duration_in_minutes
            rateLimitThreshold         = rule.rate_limit_threshold
          },
          [for _ in length(rule.group_by) > 0 ? [rule.group_by] : [] : { groupBy = [for variable in rule.group_by : { variableName = variable }] }]...
        )
      ]...
    )
  ]

  managed_rule_sets = [
    for rule_set in var.managed_rule_sets : merge(
      {
        exclusions = [
          for exclusion in rule_set.exclusions : {
            matchVariable         = exclusion.match_variable
            selector              = exclusion.selector
            selectorMatchOperator = exclusion.selector_match_operator
          }
        ]
        ruleGroupOverrides = [
          for group_name, group in rule_set.rule_group_overrides : {
            exclusions = [
              for exclusion in group.exclusions : {
                matchVariable         = exclusion.match_variable
                selector              = exclusion.selector
                selectorMatchOperator = exclusion.selector_match_operator
              }
            ]
            ruleGroupName = group_name
            rules = [
              for rule_id, rule in group.rules : merge(
                {
                  enabledState = rule.enabled ? "Enabled" : "Disabled"
                  exclusions = [
                    for exclusion in rule.exclusions : {
                      matchVariable         = exclusion.match_variable
                      selector              = exclusion.selector
                      selectorMatchOperator = exclusion.selector_match_operator
                    }
                  ]
                  ruleId = rule_id
                },
                [for action in rule.action == null ? [] : [rule.action] : { action = action }]...
              )
            ]
          }
        ]
        ruleSetType    = rule_set.type
        ruleSetVersion = rule_set.version
      },
      # The rule-set action exists for the anomaly-scoring sets (DRS 2.x) only.
      [for action in rule_set.action == null ? [] : [rule_set.action] : { ruleSetAction = action }]...
    )
  ]
}

# -----------------------------------------------------------------------------
# WAF policy
# -----------------------------------------------------------------------------

resource "azapi_resource" "this" {
  location  = "global"
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Network/frontDoorWebApplicationFirewallPolicies@2025-11-01"
  body = {
    properties = {
      customRules = {
        rules = local.custom_rules
      }
      managedRules = {
        managedRuleSets = local.managed_rule_sets
      }
      policySettings = local.policy_settings
    }
    sku = {
      name = var.sku
    }
  }
  tags = var.tags
}

# -----------------------------------------------------------------------------
# Lock
# -----------------------------------------------------------------------------

resource "azapi_resource" "lock" {
  count = var.lock != null ? 1 : 0

  name      = coalesce(var.lock.name, "lock-${var.name}")
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Authorization/locks@2020-05-01"
  body = {
    properties = {
      level = var.lock.kind
      notes = var.lock.kind == "CanNotDelete" ? "Cannot be deleted." : "Cannot be modified."
    }
  }
}

# -----------------------------------------------------------------------------
# Role assignments
# -----------------------------------------------------------------------------
# AzAPI has no equivalent of azurerm's `role_definition_name`, so role names are
# resolved against a subscription-scope listing, as the AVM interfaces module
# does.
#
# Assignment names are random UUIDs. ARM makes the name the resource identity,
# so deriving it from the principal would let an unknown-at-plan-time principal
# ID force a replacement. `name` is exposed for callers adopting an existing
# assignment.

data "azapi_resource_list" "role_definitions" {
  count = length(local.role_definition_names) > 0 ? 1 : 0

  parent_id = local.provider_subscription_resource_id
  type      = "Microsoft.Authorization/roleDefinitions@2022-04-01"
  response_export_values = {
    results = "value[].{id: id, role_name: properties.roleName}"
  }
}

resource "random_uuid" "role_assignment_name" {
  for_each = var.role_assignments
}

resource "azapi_resource" "role_assignments" {
  for_each = var.role_assignments

  name      = coalesce(each.value.name, random_uuid.role_assignment_name[each.key].result)
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  body = {
    properties = {
      condition                          = each.value.condition
      conditionVersion                   = each.value.condition_version
      delegatedManagedIdentityResourceId = each.value.delegated_managed_identity_resource_id
      description                        = each.value.description
      principalId                        = each.value.principal_id
      principalType                      = each.value.principal_type
      roleDefinitionId                   = local.role_definition_resource_ids[each.value.role_definition_id_or_name]
    }
  }

  lifecycle {
    precondition {
      # An unresolved name falls through the `lookup` default in
      # `role_definition_resource_ids` and reaches ARM as a bare string in
      # `roleDefinitionId`, which fails with an error naming neither the role nor
      # this assignment. Every resolved value is an ARM ID, so it starts with "/".
      condition     = startswith(local.role_definition_resource_ids[each.value.role_definition_id_or_name], "/")
      error_message = <<-EOT
        role_assignments["${each.key}"] names the role "${each.value.role_definition_id_or_name}",
        which matched no role definition.

        Pass a role's display name exactly as Azure spells it, or a full
        role-definition resource ID. Names resolve against the roleDefinitions
        catalogue of the provider's subscription, so a CUSTOM role defined in a
        different subscription is not listed there and must be passed as an ID.
      EOT
    }
  }
}
