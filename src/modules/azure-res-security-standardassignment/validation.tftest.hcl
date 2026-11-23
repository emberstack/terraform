# =============================================================================
# azure-res-security-standardassignment tests
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
  scope                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.ContainerService/managedClusters/aks-example"
  assigned_standard_id = "/providers/Microsoft.Security/securityStandards/11111111-1111-1111-1111-111111111111"
  assessment_key       = "22222222-2222-2222-2222-222222222222"
  exemption_category   = "mitigated"
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "required_only" {
  command = plan

  assert {
    condition = jsonencode(azapi_resource.this.body) == jsonencode({
      properties = {
        assignedStandard = { id = "/providers/Microsoft.Security/securityStandards/11111111-1111-1111-1111-111111111111" }
        effect           = "Exempt"
        exemptionData = {
          assignedAssessment = { assessmentKey = "22222222-2222-2222-2222-222222222222" }
          exemptionCategory  = "mitigated"
        }
      }
    })
    error_message = "Required inputs alone must produce an Exempt body with no optional keys."
  }

  assert {
    condition     = azapi_resource.this.parent_id == var.scope && output.scope_kind == "resource"
    error_message = "The scope must be the parent, detected as a resource."
  }

  assert {
    condition = output.name == uuidv5("url", join("|", [
      lower(var.scope),
      lower(var.assigned_standard_id),
      lower(var.assessment_key),
    ]))
    error_message = "A null name must derive the documented UUIDv5."
  }
}

run "name_ignores_scope_casing" {
  command = plan

  variables {
    scope = "/SUBSCRIPTIONS/00000000-0000-0000-0000-000000000000/RESOURCEGROUPS/rg-example/providers/Microsoft.ContainerService/managedClusters/aks-example"
  }

  assert {
    condition     = output.name == run.required_only.name
    error_message = "Scope casing alone must not change the derived name."
  }
}

run "explicit_name_and_optionals" {
  command = plan

  variables {
    name               = "33333333-3333-3333-3333-333333333333"
    scope              = "/subscriptions/00000000-0000-0000-0000-000000000000"
    exemption_category = "waiver"
    display_name       = "Controllers need API access"
    description        = "Cluster controllers call the Kubernetes API with least-privilege RBAC."
    expires_on         = "2027-06-30T00:00:00Z"
  }

  assert {
    condition     = output.name == "33333333-3333-3333-3333-333333333333" && output.scope_kind == "subscription"
    error_message = "An explicit name must be used as given."
  }

  assert {
    condition = jsonencode(azapi_resource.this.body.properties) == jsonencode({
      assignedStandard = { id = "/providers/Microsoft.Security/securityStandards/11111111-1111-1111-1111-111111111111" }
      description      = "Cluster controllers call the Kubernetes API with least-privilege RBAC."
      displayName      = "Controllers need API access"
      effect           = "Exempt"
      exemptionData = {
        assignedAssessment = { assessmentKey = "22222222-2222-2222-2222-222222222222" }
        exemptionCategory  = "waiver"
      }
      expiresOn = "2027-06-30T00:00:00Z"
    })
    error_message = "Optional fields must be sent when set."
  }
}

# =============================================================================
# NEGATIVE — variable validation
# =============================================================================

run "rejects_capitalised_category" {
  command = plan
  variables {
    exemption_category = "Mitigated"
  }
  expect_failures = [var.exemption_category]
}

run "rejects_bad_scope" {
  command = plan
  variables {
    scope = "rg-example"
  }
  expect_failures = [var.scope]
}

run "rejects_bad_standard" {
  command = plan
  variables {
    assigned_standard_id = "/providers/Microsoft.Authorization/policySetDefinitions/11111111-1111-1111-1111-111111111111"
  }
  expect_failures = [var.assigned_standard_id]
}

run "rejects_empty_assessment_key" {
  command = plan
  variables {
    assessment_key = " "
  }
  expect_failures = [var.assessment_key]
}

run "rejects_non_guid_name" {
  command = plan
  variables {
    name = "exempt-controllers"
  }
  expect_failures = [var.name]
}

run "rejects_date_only_expiry" {
  command = plan
  variables {
    expires_on = "2027-06-30"
  }
  expect_failures = [var.expires_on]
}
