# =============================================================================
# azure-res-cdn-profile tests
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
  name                = "afd-example"
  resource_group_name = "rg-example"
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans_standard_profile_with_defaults" {
  command = plan

  assert {
    condition     = azapi_resource.this.location == "global" && azapi_resource.this.body.sku.name == "Standard_AzureFrontDoor"
    error_message = "the profile must be global and default to the Standard tier"
  }
  assert {
    condition     = azapi_resource.this.body.properties.originResponseTimeoutSeconds == 60
    error_message = "the origin response timeout must default to Azure's 60 seconds"
  }
  assert {
    condition     = !contains(keys(azapi_resource.this.body.properties), "logScrubbing")
    error_message = "unset log scrubbing must be left out of the body"
  }
  assert {
    condition     = length(azapi_resource.this.identity) == 0
    error_message = "no identity block may be sent when no identity is requested"
  }
  assert {
    condition     = azapi_resource.this.parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"
    error_message = "the profile must land in the named resource group of the provider's subscription"
  }
}

run "plans_premium_profile_with_identity_scrubbing_diagnostics_and_access" {
  command = plan

  variables {
    sku = "Premium_AzureFrontDoor"
    managed_identities = {
      user_assigned_resource_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-afd"]
    }
    log_scrubbing = {
      rules = [{ match_variable = "RequestIPAddress" }]
    }
    diagnostic_settings = {
      law = {
        log_groups            = { allLogs = true }
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/law-example"
      }
    }
    role_assignments = {
      reader = {
        role_definition_id_or_name = "Reader"
        principal_id               = "11111111-1111-1111-1111-111111111111"
        principal_type             = "Group"
      }
    }
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = azapi_resource.this.body.sku.name == "Premium_AzureFrontDoor"
    error_message = "the Premium tier must be sent"
  }
  assert {
    condition     = azapi_resource.this.identity[0].type == "UserAssigned"
    error_message = "a user-assigned identity alone must be sent as UserAssigned"
  }
  assert {
    condition = (
      azapi_resource.this.body.properties.logScrubbing.state == "Enabled" &&
      azapi_resource.this.body.properties.logScrubbing.scrubbingRules[0].selectorMatchOperator == "EqualsAny" &&
      !contains(keys(azapi_resource.this.body.properties.logScrubbing.scrubbingRules[0]), "selector")
    )
    error_message = "a scrubbing rule must use EqualsAny and leave an unset selector out"
  }
  assert {
    condition     = azapi_resource.diagnostic_settings["law"].body.properties.logs[0].categoryGroup == "allLogs"
    error_message = "the diagnostic setting must carry the requested log group"
  }
  assert {
    condition     = azapi_resource.role_assignments["reader"].body.properties.roleDefinitionId == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
    error_message = "a role name must resolve to its definition ID"
  }
  assert {
    condition     = azapi_resource.lock[0].name == "lock-afd-example" && azapi_resource.lock[0].body.properties.level == "CanNotDelete"
    error_message = "the lock must default to lock-<name>"
  }
}

# =============================================================================
# NEGATIVE — variable validation
# =============================================================================

run "rejects_a_classic_cdn_sku" {
  command = plan

  variables {
    sku = "Standard_Microsoft"
  }

  expect_failures = [var.sku]
}

run "rejects_a_name_ending_in_a_hyphen" {
  command = plan

  variables {
    name = "afd-example-"
  }

  expect_failures = [var.name]
}

run "rejects_an_origin_timeout_below_16_seconds" {
  command = plan

  variables {
    origin_response_timeout_seconds = 10
  }

  expect_failures = [var.origin_response_timeout_seconds]
}

run "rejects_an_unknown_scrubbing_variable" {
  command = plan

  variables {
    log_scrubbing = {
      rules = [{ match_variable = "RequestCookieNames" }]
    }
  }

  expect_failures = [var.log_scrubbing]
}

run "rejects_a_diagnostic_setting_with_two_destinations" {
  command = plan

  variables {
    diagnostic_settings = {
      both = {
        workspace_resource_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/law-example"
        storage_account_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Storage/storageAccounts/stexample"
      }
    }
  }

  expect_failures = [var.diagnostic_settings]
}

run "rejects_an_unknown_lock_kind" {
  command = plan

  variables {
    lock = { kind = "Delete" }
  }

  expect_failures = [var.lock]
}
