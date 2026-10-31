# =============================================================================
# AZURE APPLICATION GATEWAY WAF POLICY
# (Microsoft.Network/applicationGatewayWebApplicationFirewallPolicies)
# =============================================================================
# A WAF policy for Application Gateway or Application Gateway for Containers:
# policy settings, custom rules, managed rule sets with per-rule overrides, and
# exclusions. Attaching the policy is the gateway's job, not this module's.
#
# The type is spelled with a lowercase `a`, as ARM spells it in resource IDs,
# so `resource_id` is the exact string ARM and azurerm hand out. Consumers that
# key on the ID (role assignment scopes, AGC policy references) see no change.
#
# List order is part of the body, so it follows the inputs: custom rules and
# override groups/rules in map-key order, exclusions and their rule groups in
# list order. ARM keeps the order it is sent.
#
# Optional properties ARM omits when unset (an override's `action`, a match
# variable's `selector`, rate-limit settings, log scrubbing) are left out of the
# body rather than sent as null.
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

  # Optional keys are added with `merge(base, [for _ in <0 or 1 items> : {...}]...)`:
  # a conditional between `{}` and an object with attributes is a type error.
  policy_settings = merge(
    {
      fileUploadEnforcement             = var.policy_settings.file_upload_enforcement
      fileUploadLimitInMb               = var.policy_settings.file_upload_limit_in_mb
      jsChallengeCookieExpirationInMins = var.policy_settings.js_challenge_cookie_expiration_in_minutes
      maxRequestBodySizeInKb            = var.policy_settings.max_request_body_size_in_kb
      mode                              = var.policy_settings.mode
      requestBodyCheck                  = var.policy_settings.request_body_check
      requestBodyEnforcement            = var.policy_settings.request_body_enforcement
      requestBodyInspectLimitInKB       = var.policy_settings.request_body_inspect_limit_in_kb
      state                             = var.policy_settings.enabled ? "Enabled" : "Disabled"
    },
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
        action = rule.action
        matchConditions = [
          for condition in rule.match_conditions : {
            matchValues = condition.match_values
            matchVariables = [
              for variable in condition.match_variables : merge(
                { variableName = variable.variable_name },
                [for selector in variable.selector == null ? [] : [variable.selector] : { selector = selector }]...
              )
            ]
            negationConditon = condition.negation_condition # sic: ARM's property name
            operator         = condition.operator
            transforms       = condition.transforms
          }
        ]
        name     = name
        priority = rule.priority
        ruleType = rule.rule_type
        state    = rule.enabled ? "Enabled" : "Disabled"
      },
      [
        for _ in rule.rule_type == "RateLimitRule" ? [rule] : [] : merge(
          {
            rateLimitDuration  = rule.rate_limit_duration
            rateLimitThreshold = rule.rate_limit_threshold
          },
          [
            for variable in rule.group_rate_limit_by == null ? [] : [rule.group_rate_limit_by] : {
              groupByUserSession = [{ groupByVariables = [{ variableName = variable }] }]
            }
          ]...
        )
      ]...
    )
  ]

  managed_rule_sets = [
    for rule_set in var.managed_rules.managed_rule_sets : {
      ruleGroupOverrides = [
        for group_name, group in rule_set.rule_group_overrides : {
          ruleGroupName = group_name
          rules = [
            for rule_id, rule in group.rules : merge(
              {
                ruleId = rule_id
                state  = rule.enabled ? "Enabled" : "Disabled"
              },
              [for action in rule.action == null ? [] : [rule.action] : { action = action }]...
            )
          ]
        }
      ]
      ruleSetType    = rule_set.type
      ruleSetVersion = rule_set.version
    }
  ]

  exclusions = [
    for exclusion in var.managed_rules.exclusions : {
      exclusionManagedRuleSets = [
        for rule_set in exclusion.excluded_rule_set == null ? [] : [exclusion.excluded_rule_set] : {
          ruleGroups = [
            for group in rule_set.rule_groups : {
              ruleGroupName = group.rule_group_name
              rules         = [for rule_id in group.excluded_rules : { ruleId = rule_id }]
            }
          ]
          ruleSetType    = rule_set.type
          ruleSetVersion = rule_set.version
        }
      ]
      matchVariable         = exclusion.match_variable
      selector              = exclusion.selector
      selectorMatchOperator = exclusion.selector_match_operator
    }
  ]
}

# -----------------------------------------------------------------------------
# WAF policy
# -----------------------------------------------------------------------------

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Network/applicationGatewayWebApplicationFirewallPolicies@2025-07-01"
  body = {
    properties = {
      customRules = local.custom_rules
      managedRules = {
        exclusions      = local.exclusions
        managedRuleSets = local.managed_rule_sets
      }
      policySettings = local.policy_settings
    }
  }
  tags = var.tags
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
