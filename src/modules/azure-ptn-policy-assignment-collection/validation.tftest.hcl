# =============================================================================
# azure-ptn-policy-assignment-collection tests
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

  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mcsb"
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
  assignments = {
    mcsb = {
      name                 = "SecurityCenterBuiltIn"
      scope                = "/subscriptions/00000000-0000-0000-0000-000000000000"
      policy_definition_id = "/providers/Microsoft.Authorization/policySetDefinitions/e3ec7e09-768c-4b64-882c-fcada3772047"
      display_name         = "Microsoft cloud security benchmark"
      description          = "Default Defender for Cloud initiative."
      parameters           = "{\"kubernetesClusterAllowedContainerImagesRegex\":{\"value\":\"^x\"}}"
      location             = "westeurope"
      managed_identities   = { system_assigned = true }
      identity_role_assignments = {
        reader = { role_definition_id_or_name = "Reader" }
      }
    }
    locations = {
      name                 = "allowed-locations"
      scope                = "/subscriptions/00000000-0000-0000-0000-000000000000"
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
      parameters           = "{\"listOfAllowedLocations\":{\"value\":[\"westeurope\",\"northeurope\"]}}"
      enforce              = false
      not_scopes           = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-b", "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-a"]
      non_compliance_messages = [
        { content = "Deploy to West or North Europe only." },
      ]
      resource_selectors = {
        eu = [{ kind = "resourceLocation", in = ["westeurope"] }]
      }
    }
    nis2 = {
      name                 = "nis2-2022-2555"
      scope                = "/subscriptions/00000000-0000-0000-0000-000000000000"
      policy_definition_id = "/providers/Microsoft.Authorization/policySetDefinitions/42346945-b531-41d8-9e46-f95057672e88"
      display_name         = "NIS2 (EU 2022/2555)"
    }
  }
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "assignments" {
  command = apply

  assert {
    condition = jsonencode(azapi_resource.this["nis2"].body) == jsonencode({
      properties = {
        displayName        = "NIS2 (EU 2022/2555)"
        enforcementMode    = "Default"
        policyDefinitionId = "/providers/Microsoft.Authorization/policySetDefinitions/42346945-b531-41d8-9e46-f95057672e88"
      }
    })
    error_message = "Unset optional fields must be left out of the body, not sent as null."
  }

  assert {
    condition = jsonencode(azapi_resource.this["locations"].body) == jsonencode({
      properties = {
        enforcementMode       = "DoNotEnforce"
        nonComplianceMessages = [{ message = "Deploy to West or North Europe only." }]
        notScopes = [
          "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-a",
          "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-b",
        ]
        parameters         = { listOfAllowedLocations = { value = ["westeurope", "northeurope"] } }
        policyDefinitionId = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
        resourceSelectors  = [{ name = "eu", selectors = [{ in = ["westeurope"], kind = "resourceLocation" }] }]
      }
    })
    error_message = "A list-valued parameter must reach the body decoded, beside other entries' string-valued ones."
  }

  assert {
    condition = (
      azapi_resource.this["mcsb"].identity[0].type == "SystemAssigned" &&
      azapi_resource.this["mcsb"].location == "westeurope" &&
      length(azapi_resource.this["nis2"].identity) == 0
    )
    error_message = "Only the assignment asking for one may get a system-assigned identity."
  }

  assert {
    condition = (
      azapi_resource.identity_role_assignments["mcsb-reader"].parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000" &&
      azapi_resource.identity_role_assignments["mcsb-reader"].body.properties.roleDefinitionId == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
    )
    error_message = "A role name must resolve to its definition ID, at the assignment's scope by default."
  }

  assert {
    condition = (
      output.assignments["mcsb"].system_assigned_mi_principal_id != null &&
      output.assignments["nis2"].system_assigned_mi_principal_id == null &&
      keys(output.assignments["mcsb"].identity_role_assignments) == ["reader"]
    )
    error_message = "Outputs must carry the identity and regroup role assignments under their assignment."
  }
}

# =============================================================================
# NEGATIVE — variable validation
# =============================================================================

run "rejects_bad_key" {
  command = plan
  variables {
    assignments = {
      "nis-2" = { name = "nis2", scope = "/subscriptions/00000000-0000-0000-0000-000000000000", policy_definition_id = "/providers/Microsoft.Authorization/policySetDefinitions/x" }
    }
  }
  expect_failures = [var.assignments]
}

run "rejects_bad_scope" {
  command = plan
  variables {
    assignments = {
      nis2 = { name = "nis2", scope = "subscriptions/00000000-0000-0000-0000-000000000000", policy_definition_id = "/providers/Microsoft.Authorization/policySetDefinitions/x" }
    }
  }
  expect_failures = [var.assignments]
}

run "rejects_long_name_at_management_group" {
  command = plan
  variables {
    assignments = {
      nis2 = { name = "nis2-2022-2555-management-group", scope = "/providers/Microsoft.Management/managementGroups/mg", policy_definition_id = "/providers/Microsoft.Authorization/policySetDefinitions/x" }
    }
  }
  expect_failures = [var.assignments]
}

run "rejects_parameters_not_json_object" {
  command = plan
  variables {
    assignments = {
      nis2 = { name = "nis2", scope = "/subscriptions/00000000-0000-0000-0000-000000000000", policy_definition_id = "/providers/Microsoft.Authorization/policySetDefinitions/x", parameters = "[1]" }
    }
  }
  expect_failures = [var.assignments]
}

run "rejects_identity_without_location" {
  command = plan
  variables {
    assignments = {
      nis2 = { name = "nis2", scope = "/subscriptions/00000000-0000-0000-0000-000000000000", policy_definition_id = "/providers/Microsoft.Authorization/policySetDefinitions/x", managed_identities = { system_assigned = true } }
    }
  }
  expect_failures = [var.assignments]
}

run "rejects_bad_role_assignment_name" {
  command = plan
  variables {
    assignments = {
      nis2 = {
        name                      = "nis2"
        scope                     = "/subscriptions/00000000-0000-0000-0000-000000000000"
        policy_definition_id      = "/providers/Microsoft.Authorization/policySetDefinitions/x"
        location                  = "westeurope"
        managed_identities        = { system_assigned = true }
        identity_role_assignments = { reader = { name = "not-a-guid", role_definition_id_or_name = "Reader" } }
      }
    }
  }
  expect_failures = [var.assignments]
}
