# =============================================================================
# azure-res-network-networkmanager tests
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
            id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"
            role_name = "Network Contributor"
          },
        ]
      }
    }
  }
}

mock_provider "random" {}

variables {
  name                = "avnm-example"
  resource_group_name = "rg-example"
  location            = "westeurope"
  network_manager_scope = {
    subscription_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000"]
  }
  network_manager_scope_accesses = ["Connectivity", "SecurityAdmin", "Routing"]
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans_subscription_scoped_manager" {
  command = plan

  assert {
    condition     = azapi_resource.this.parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"
    error_message = "the manager must be parented on the resource group in the provider's subscription"
  }
  assert {
    condition     = azapi_resource.this.body.properties.networkManagerScopes.subscriptions == tolist(["/subscriptions/00000000-0000-0000-0000-000000000000"]) && length(azapi_resource.this.body.properties.networkManagerScopes.managementGroups) == 0
    error_message = "scopes must pass through, with management groups sent as an empty list"
  }
  assert {
    condition     = azapi_resource.this.body.properties.networkManagerScopeAccesses == tolist(["Connectivity", "SecurityAdmin", "Routing"])
    error_message = "scope accesses must keep the order given"
  }
  assert {
    condition     = azapi_resource.this.body.properties.description == null && length(azapi_resource.role_assignments) == 0
    error_message = "description and role assignments must stay unset unless asked for"
  }
  assert {
    condition     = output.resource_group_name == "rg-example" && output.role_assignments == {}
    error_message = "outputs must evaluate"
  }
}

run "plans_management_group_scope_with_roles" {
  command = plan

  variables {
    description = "Platform network manager"
    network_manager_scope = {
      management_group_ids = ["/providers/Microsoft.Management/managementGroups/mg-platform"]
    }
    network_manager_scope_accesses = []
    role_assignments = {
      netcontrib = {
        role_definition_id_or_name = "Network Contributor"
        principal_id               = "11111111-1111-1111-1111-111111111111"
        principal_type             = "Group"
      }
    }
  }

  assert {
    condition     = azapi_resource.this.body.properties.networkManagerScopes.managementGroups == tolist(["/providers/Microsoft.Management/managementGroups/mg-platform"])
    error_message = "management group scopes must pass through"
  }
  assert {
    condition     = length(azapi_resource.this.body.properties.networkManagerScopeAccesses) == 0 && azapi_resource.this.body.properties.description == "Platform network manager"
    error_message = "an empty scope-access list and the description must pass through"
  }
  assert {
    condition     = endswith(azapi_resource.role_assignments["netcontrib"].body.properties.roleDefinitionId, "/4d97b98b-1d4f-4787-a291-c67834d212e7")
    error_message = "a role name must resolve to its definition ID"
  }
  assert {
    condition     = output.role_assignments["netcontrib"].principal_id == "11111111-1111-1111-1111-111111111111"
    error_message = "outputs must evaluate"
  }
}

# =============================================================================
# NEGATIVE — each validation must fire
# =============================================================================

run "rejects_name_ending_in_hyphen" {
  command = plan
  variables {
    name = "avnm-"
  }
  expect_failures = [var.name]
}

run "rejects_name_longer_than_64" {
  command = plan
  variables {
    name = join("", [for i in range(65) : "a"])
  }
  expect_failures = [var.name]
}

run "rejects_empty_scope" {
  command = plan
  variables {
    network_manager_scope = {}
  }
  expect_failures = [var.network_manager_scope]
}

run "rejects_bare_subscription_guid" {
  command = plan
  variables {
    network_manager_scope = {
      subscription_ids = ["00000000-0000-0000-0000-000000000000"]
    }
  }
  expect_failures = [var.network_manager_scope]
}

run "rejects_management_group_name_without_prefix" {
  command = plan
  variables {
    network_manager_scope = {
      management_group_ids = ["mg-platform"]
    }
  }
  expect_failures = [var.network_manager_scope]
}

run "rejects_unknown_scope_access" {
  command = plan
  variables {
    network_manager_scope_accesses = ["Connectivity", "Peering"]
  }
  expect_failures = [var.network_manager_scope_accesses]
}

run "rejects_repeated_scope_access" {
  command = plan
  variables {
    network_manager_scope_accesses = ["Connectivity", "Connectivity"]
  }
  expect_failures = [var.network_manager_scope_accesses]
}

run "rejects_resource_group_id" {
  command = plan
  variables {
    resource_group_name = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"
  }
  expect_failures = [var.resource_group_name]
}

run "rejects_uppercase_role_assignment_name" {
  command = plan
  variables {
    role_assignments = {
      netcontrib = {
        name                       = "11111111-1111-1111-1111-11111111111A"
        role_definition_id_or_name = "Network Contributor"
        principal_id               = "11111111-1111-1111-1111-111111111111"
      }
    }
  }
  expect_failures = [var.role_assignments]
}
