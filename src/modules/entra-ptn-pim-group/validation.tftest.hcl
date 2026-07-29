# =============================================================================
# entra-ptn-pim-group tests
# =============================================================================
# `mock_provider` keeps the whole suite offline: negative runs abort during
# variable validation and never reach a provider, and the positive runs need a
# resource graph but not a real tenant.
#
# The positive runs matter more than they look. Every negative run short-circuits
# at variable validation, so an `expect_failures`-only suite never constructs the
# resource graph and never evaluates the outputs — which is precisely how a
# reference to a nonexistent provider attribute survived `terraform validate`,
# `terraform fmt` and a fully green suite. Any run below that plans a populated
# `policies`/`eligibility`/`assignments` map and asserts on the matching output
# is what closes that hole; keep at least one of each.
#
# Caveat: mocking bypasses the provider's own ValidateDiagFunc, so the positive
# runs cannot confirm a value is acceptable to Entra. The variable validation
# blocks are the guard for that.
# =============================================================================

mock_provider "azuread" {}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans_assignments_and_evaluates_outputs" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    assignments = {
      ops = {
        principal       = "11111111-1111-1111-1111-111111111111"
        assignment_type = "member"
        duration        = "P30D"
      }
    }
  }

  assert {
    condition     = azuread_privileged_access_group_assignment_schedule.this["ops"].duration == "P30D"
    error_message = "duration should pass through unchanged"
  }
  assert {
    condition     = output.assignments["ops"].principal_id == "11111111-1111-1111-1111-111111111111"
    error_message = "the assignments output must evaluate — this is the run that catches bad attribute references"
  }
}

run "plans_eligibility_permanent" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    eligibility = {
      crew = {
        principal       = "22222222-2222-2222-2222-222222222222"
        assignment_type = "member"
      }
    }
  }

  assert {
    condition     = azuread_privileged_access_group_eligibility_schedule.this["crew"].permanent_assignment == true
    error_message = "omitting duration must derive permanent_assignment = true"
  }
  assert {
    condition     = azuread_privileged_access_group_eligibility_schedule.this["crew"].duration == null
    error_message = "permanent eligibility must not send a duration"
  }
  assert {
    condition     = output.eligibility["crew"].assignment_type == "member"
    error_message = "the eligibility output must evaluate"
  }
}

run "derives_expiration_tristate" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies = {
      member = { active_assignments = { expiration = "permitted" } }
      owner  = { active_assignments = { expiration = "P90D" } }
    }
  }

  assert {
    condition     = azuread_group_role_management_policy.this["member"].active_assignment_rules[0].expiration_required == false
    error_message = "\"permitted\" must derive expiration_required = false"
  }
  assert {
    condition     = azuread_group_role_management_policy.this["owner"].active_assignment_rules[0].expiration_required == true
    error_message = "an explicit duration must derive expiration_required = true"
  }
  assert {
    condition     = azuread_group_role_management_policy.this["owner"].active_assignment_rules[0].expire_after == "P90D"
    error_message = "expire_after must carry the chosen maximum"
  }
  assert {
    condition     = length(output.policies) == 2
    error_message = "the policies output must evaluate"
  }
}

run "expiration_required_keeps_adopted_duration" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies        = { member = { eligible_assignments = { expiration = "required" } } }
  }

  assert {
    condition     = azuread_group_role_management_policy.this["member"].eligible_assignment_rules[0].expiration_required == true
    error_message = "\"required\" must harden expiration_required"
  }
  # The companion property — that expire_after is left unset so the adopted
  # maximum is inherited — is not assertable here: expire_after is
  # Optional+Computed, so an unset value is unknown at plan and a mocked apply
  # would invent one. Verified instead against the real provider, which renders
  # it as "(known after apply)".
}

run "derives_approvers_tristate" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies = {
      member = {
        activation = {
          approvers = {
            leads = { object_id = "11111111-1111-1111-1111-111111111111", type = "groupMembers" }
          }
        }
      }
      owner = { activation = { approvers = {} } }
    }
  }

  assert {
    condition     = azuread_group_role_management_policy.this["member"].activation_rules[0].require_approval == true
    error_message = "populated approvers must require approval"
  }
  assert {
    condition     = length(azuread_group_role_management_policy.this["member"].activation_rules[0].approval_stage) == 1
    error_message = "populated approvers must emit an approval stage"
  }
  assert {
    condition     = azuread_group_role_management_policy.this["owner"].activation_rules[0].require_approval == false
    error_message = "an empty approvers map must explicitly disable approval"
  }
  # Not asserted: that no approval_stage is emitted for the empty map. The block
  # is Computed, so its absence reads as unknown at plan rather than as an empty
  # list. Verified against the real provider as "approval_stage (known after apply)".
}

run "derives_authentication_gate" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies = {
      member = { activation = { authentication = { method = "mfa" } } }
      owner  = { activation = { authentication = { method = "conditional_access", authentication_context = "c1" } } }
    }
  }

  assert {
    condition     = azuread_group_role_management_policy.this["member"].activation_rules[0].require_multifactor_authentication == true
    error_message = "method \"mfa\" must set require_multifactor_authentication"
  }
  assert {
    condition     = azuread_group_role_management_policy.this["owner"].activation_rules[0].required_conditional_access_authentication_context == "c1"
    error_message = "method \"conditional_access\" must pass the auth context through"
  }
}

# A UPN principal must route through the azuread_user data source; a UUID must
# bypass it. `override_data` is required rather than optional here: mock_provider
# generates a short random string for object_id, and the provider's own
# ValidateDiagFunc on principal_id rejects anything that is not a UUID, so the
# mocked default fails the resource before any assertion runs. Overriding it also
# lets the resolved value be asserted exactly instead of merely "not the UPN".
run "resolves_upn_principal" {
  command = plan

  override_data {
    target = data.azuread_user.this["alice@example.com"]
    values = {
      object_id = "33333333-3333-3333-3333-333333333333"
    }
  }

  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    eligibility = {
      alice = { principal = "alice@example.com", assignment_type = "member" }
      bob   = { principal = "22222222-2222-2222-2222-222222222222", assignment_type = "member" }
    }
  }

  assert {
    condition     = azuread_privileged_access_group_eligibility_schedule.this["alice"].principal_id == "33333333-3333-3333-3333-333333333333"
    error_message = "a UPN principal must be resolved through the azuread_user lookup"
  }
  assert {
    condition     = azuread_privileged_access_group_eligibility_schedule.this["bob"].principal_id == "22222222-2222-2222-2222-222222222222"
    error_message = "a UUID principal must be used directly, not sent to the user lookup"
  }
  assert {
    condition     = length(data.azuread_user.this) == 1
    error_message = "only the UPN entry should produce a directory lookup"
  }
}

run "accepts_p1d_maximum_duration" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies        = { member = { activation = { maximum_duration = "P1D" } } }
  }

  assert {
    condition     = azuread_group_role_management_policy.this["member"].activation_rules[0].maximum_duration == "P1D"
    error_message = "P1D is the provider's 24-hour value and must be accepted"
  }
}

# =============================================================================
# NEGATIVE — every guard must actually fire
# =============================================================================

run "rejects_nothing_configured" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
  }
  expect_failures = [var.assignments]
}

run "rejects_bad_group_object_id" {
  command = plan
  variables {
    group_object_id = "not-a-uuid"
    policies        = { member = {} }
  }
  expect_failures = [var.group_object_id]
}

run "rejects_unknown_policy_role" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies        = { admin = {} }
  }
  expect_failures = [var.policies]
}

run "rejects_bad_authentication_method" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies        = { member = { activation = { authentication = { method = "smartcard" } } } }
  }
  expect_failures = [var.policies]
}

run "rejects_null_authentication_method" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies        = { member = { activation = { authentication = { method = null } } } }
  }
  expect_failures = [var.policies]
}

# The ConflictsWith pair: an auth context alongside the mfa method.
run "rejects_mfa_with_authentication_context" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies = {
      member = { activation = { authentication = { method = "mfa", authentication_context = "c1" } } }
    }
  }
  expect_failures = [var.policies]
}

run "rejects_conditional_access_without_context" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies        = { member = { activation = { authentication = { method = "conditional_access" } } } }
  }
  expect_failures = [var.policies]
}

run "rejects_bad_maximum_duration" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies        = { member = { activation = { maximum_duration = "PT25H" } } }
  }
  expect_failures = [var.policies]
}

# PT1D looks plausible and is what the registry docs imply, but the provider's
# enum ends with P1D. Regression guard for a regex that admitted the wrong one.
run "rejects_pt1d_maximum_duration" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies        = { member = { activation = { maximum_duration = "PT1D" } } }
  }
  expect_failures = [var.policies]
}

run "rejects_bad_approver_type" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies = {
      member = {
        activation = {
          approvers = { leads = { object_id = "11111111-1111-1111-1111-111111111111", type = "Group" } }
        }
      }
    }
  }
  expect_failures = [var.policies]
}

run "rejects_non_uuid_approver" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies = {
      member = {
        activation = {
          approvers = { leads = { object_id = "alice@example.com", type = "singleUser" } }
        }
      }
    }
  }
  expect_failures = [var.policies]
}

run "rejects_bad_expiration_value" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies        = { member = { active_assignments = { expiration = "P60D" } } }
  }
  expect_failures = [var.policies]
}

run "rejects_notification_event_with_no_recipient" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies        = { member = { notifications = { eligible_assignments = {} } } }
  }
  expect_failures = [var.policies]
}

run "rejects_bad_assignment_type" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    eligibility = {
      crew = { principal = "11111111-1111-1111-1111-111111111111", assignment_type = "admin" }
    }
  }
  expect_failures = [var.eligibility]
}

run "rejects_malformed_principal" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    eligibility = {
      crew = { principal = "not-a-user", assignment_type = "member" }
    }
  }
  expect_failures = [var.eligibility]
}

# The cross-variable guard, covering "required" as well as an explicit maximum.
run "rejects_permanent_eligibility_against_expiring_policy" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies        = { member = { eligible_assignments = { expiration = "P90D" } } }
    eligibility = {
      crew = { principal = "11111111-1111-1111-1111-111111111111", assignment_type = "member" }
    }
  }
  expect_failures = [var.eligibility]
}

run "rejects_permanent_eligibility_against_required_policy" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies        = { member = { eligible_assignments = { expiration = "required" } } }
    eligibility = {
      crew = { principal = "11111111-1111-1111-1111-111111111111", assignment_type = "member" }
    }
  }
  expect_failures = [var.eligibility]
}

run "rejects_permanent_assignment_against_expiring_policy" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    policies        = { member = { active_assignments = { expiration = "P90D" } } }
    assignments = {
      ops = { principal = "11111111-1111-1111-1111-111111111111", assignment_type = "member" }
    }
  }
  expect_failures = [var.assignments]
}

run "rejects_bad_duration_format" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    eligibility = {
      crew = {
        principal       = "11111111-1111-1111-1111-111111111111"
        assignment_type = "member"
        duration        = "30 days"
      }
    }
  }
  expect_failures = [var.eligibility]
}

# Degenerate ISO8601 forms, every component of which is optional.
run "rejects_dangling_duration_designator" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    eligibility = {
      crew = {
        principal       = "11111111-1111-1111-1111-111111111111"
        assignment_type = "member"
        duration        = "PT"
      }
    }
  }
  expect_failures = [var.eligibility]
}

run "rejects_zero_duration" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    eligibility = {
      crew = {
        principal       = "11111111-1111-1111-1111-111111111111"
        assignment_type = "member"
        duration        = "P0D"
      }
    }
  }
  expect_failures = [var.eligibility]
}

run "rejects_bad_start_date" {
  command = plan
  variables {
    group_object_id = "00000000-0000-0000-0000-000000000001"
    eligibility = {
      crew = {
        principal       = "11111111-1111-1111-1111-111111111111"
        assignment_type = "member"
        start_date      = "tomorrow"
      }
    }
  }
  expect_failures = [var.eligibility]
}
