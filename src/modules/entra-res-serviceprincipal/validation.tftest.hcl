# =============================================================================
# entra-res-serviceprincipal tests
# =============================================================================
# `mock_provider` keeps the suite offline: negative runs abort during variable
# validation, and the positive runs need a resource graph but not a tenant.
#
# The positive runs are the ones that construct the resource graph and evaluate
# the outputs — an `expect_failures`-only suite never does, so a bad attribute
# reference would pass it green.
# =============================================================================

mock_provider "azuread" {
  mock_data "azuread_user" {
    defaults = {
      object_id = "22222222-2222-2222-2222-222222222222"
    }
  }
}

variables {
  client_id = "2565bd9d-da50-47d4-8b85-4c97f669dc36"
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans_minimal_service_principal" {
  command = plan

  assert {
    condition     = azuread_service_principal.this.client_id == var.client_id
    error_message = "the service principal must instantiate client_id"
  }
  assert {
    condition     = azuread_service_principal.this.use_existing == false
    error_message = "adopting an existing service principal must be opt-in"
  }
  assert {
    condition     = azuread_service_principal.this.account_enabled == true && azuread_service_principal.this.app_role_assignment_required == false
    error_message = "the service principal must default to enabled and open to all users"
  }
  assert {
    condition     = length(azuread_service_principal.this.owners) == 0
    error_message = "no owners unless asked for"
  }
  assert {
    condition     = length(data.azuread_user.owners) == 0
    error_message = "no Graph lookups without UPN owners"
  }
  assert {
    condition     = output.client_id == var.client_id
    error_message = "the outputs must evaluate — this is the run that catches bad attribute references"
  }
}

run "plans_adopted_service_principal_with_owners" {
  command = plan

  variables {
    use_existing                 = true
    app_role_assignment_required = true
    notes                        = "Required by Entra Domain Services."
    tags                         = ["example"]
    owners = {
      alice = "alice@example.com"
      bob   = "11111111-1111-1111-1111-111111111111"
    }
  }

  assert {
    condition     = azuread_service_principal.this.use_existing == true
    error_message = "use_existing must be passed through"
  }
  assert {
    condition     = azuread_service_principal.this.app_role_assignment_required == true
    error_message = "app_role_assignment_required must be passed through"
  }
  assert {
    condition     = toset(azuread_service_principal.this.owners) == toset(["11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"])
    error_message = "UUID owners must be used directly and UPN owners resolved to their object IDs"
  }
  assert {
    condition     = length(data.azuread_user.owners) == 1 && contains(keys(data.azuread_user.owners), "alice@example.com")
    error_message = "only UPN owners may be looked up in Graph"
  }
  assert {
    condition     = azuread_service_principal.this.tags == toset(["example"])
    error_message = "tags must be passed through when set"
  }
}

# =============================================================================
# NEGATIVE — validation must reject before anything reaches Graph
# =============================================================================

run "rejects_non_uuid_client_id" {
  command = plan

  variables {
    client_id = "Domain Controller Services"
  }

  expect_failures = [var.client_id]
}

run "rejects_invalid_owner" {
  command = plan

  variables {
    owners = {
      nobody = "not-a-principal"
    }
  }

  expect_failures = [var.owners]
}

run "rejects_overlong_description" {
  command = plan

  variables {
    description = format("%1025s", "x")
  }

  expect_failures = [var.description]
}
