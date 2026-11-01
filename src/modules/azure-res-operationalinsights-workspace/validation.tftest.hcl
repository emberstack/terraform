# =============================================================================
# azure-res-operationalinsights-workspace tests
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

  # A valid ARM ID, because an apply run leaves the workspace in the shared test
  # state and parents children and role assignments on it.
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/law-example"
    }
  }

  mock_data "azapi_resource_list" {
    defaults = {
      output = {
        results = [
          {
            id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/92aaf0da-9dab-42b6-94a3-d43ce8d16293"
            role_name = "Log Analytics Contributor"
          },
        ]
      }
    }
  }
}

mock_provider "random" {}

variables {
  name                = "law-example"
  resource_group_name = "rg-example"
  location            = "westeurope"
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "defaults" {
  command = plan

  assert {
    condition = jsonencode(azapi_resource.this.body) == jsonencode({
      properties = {
        features = {
          disableLocalAuth                            = false
          enableLogAccessUsingOnlyResourcePermissions = true
        }
        forceCmkForQuery                = false
        publicNetworkAccessForIngestion = "Enabled"
        publicNetworkAccessForQuery     = "Enabled"
        retentionInDays                 = 30
        sku                             = { name = "PerGB2018" }
        workspaceCapping                = { dailyQuotaGb = -1 }
      }
    })
    error_message = "Defaults must be Azure's: PerGB2018, 30 days, no cap, public access, local auth, resource-context access."
  }

  assert {
    condition     = length(azapi_resource.this.identity) == 0
    error_message = "No identity must be requested by default."
  }

  assert {
    condition = (
      length(azapi_resource.data_collection_rule) == 0 &&
      length(azapi_update_resource.default_data_collection_rule) == 0 &&
      length(azapi_resource.sentinel_onboarding) == 0 &&
      length(azapi_resource.linked_storage_accounts) == 0
    )
    error_message = "No children must be created by default."
  }

  assert {
    condition     = output.data_collection_rule_resource_id == null && output.role_assignments == {}
    error_message = "Outputs must evaluate with no children."
  }
}

run "children" {
  command = apply

  variables {
    retention_in_days    = 90
    daily_quota_gb       = 30
    cmk_for_query_forced = true
    managed_identities   = { system_assigned = true }

    workspace_transforms = {
      name = "law-example-dcr"
      table_transforms = {
        AppRequests = { transform_kql = "source\n| where Success == false\n" }
        AppMetrics  = { transform_kql = "source | where not(Name startswith \"http.\")", description = "noise" }
      }
    }

    sentinel_onboarding_enabled = true
    linked_storage_accounts = {
      Query = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Storage/storageAccounts/stexample"]
    }

    role_assignments = {
      contributor = {
        role_definition_id_or_name = "Log Analytics Contributor"
        principal_id               = "11111111-1111-1111-1111-111111111111"
        principal_type             = "Group"
      }
    }
  }

  assert {
    condition     = azapi_resource.this.identity[0].type == "SystemAssigned"
    error_message = "A system-assigned identity must be requested."
  }

  assert {
    condition = (
      azapi_resource.this.body.properties.forceCmkForQuery == true &&
      azapi_resource.this.body.properties.retentionInDays == 90 &&
      azapi_resource.this.body.properties.workspaceCapping.dailyQuotaGb == 30
    )
    error_message = "Workspace settings must reach the body."
  }

  # Data flows follow table-name order: AppMetrics before AppRequests.
  assert {
    condition = jsonencode(azapi_resource.data_collection_rule[0].body) == jsonencode({
      kind = "WorkspaceTransforms"
      properties = {
        dataFlows = [
          { destinations = ["workspace"], streams = ["Microsoft-Table-AppMetrics"], transformKql = "source | where not(Name startswith \"http.\")" },
          { destinations = ["workspace"], streams = ["Microsoft-Table-AppRequests"], transformKql = "source\n| where Success == false\n" },
        ]
        description = "Ingestion-time transformations for workspace tables"
        destinations = {
          logAnalytics = [
            {
              name                = "workspace"
              workspaceResourceId = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/law-example"
            },
          ]
        }
      }
    })
    error_message = "The transformation DCR body does not match the expected shape."
  }

  assert {
    condition     = azapi_update_resource.default_data_collection_rule[0].body.properties.defaultDataCollectionRuleResourceId == azapi_resource.data_collection_rule[0].id
    error_message = "The workspace must be linked to the transformation DCR."
  }

  assert {
    condition     = azapi_resource.sentinel_onboarding[0].name == "default" && azapi_resource.linked_storage_accounts["Query"].name == "Query"
    error_message = "Sentinel onboarding and linked storage must be created with ARM's fixed names."
  }

  assert {
    condition     = azapi_resource.role_assignments["contributor"].body.properties.roleDefinitionId == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/92aaf0da-9dab-42b6-94a3-d43ce8d16293"
    error_message = "A role name must resolve to its definition ID."
  }

  assert {
    condition     = output.data_collection_rule_resource_id != null && output.role_assignments["contributor"].principal_id == "11111111-1111-1111-1111-111111111111"
    error_message = "Outputs must carry the DCR and the role assignment."
  }
}

# =============================================================================
# NEGATIVE — variable validation
# =============================================================================

run "rejects_bad_name" {
  command = plan
  variables {
    name = "law"
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

run "rejects_bad_sku" {
  command = plan
  variables {
    sku = "Basic"
  }
  expect_failures = [var.sku]
}

run "rejects_retention_out_of_range" {
  command = plan
  variables {
    retention_in_days = 20
  }
  expect_failures = [var.retention_in_days]
}

run "rejects_zero_quota" {
  command = plan
  variables {
    daily_quota_gb = 0
  }
  expect_failures = [var.daily_quota_gb]
}

run "rejects_bad_network_access" {
  command = plan
  variables {
    public_network_access_for_query = "Private"
  }
  expect_failures = [var.public_network_access_for_query]
}

run "rejects_both_identity_types" {
  command = plan
  variables {
    managed_identities = {
      system_assigned            = true
      user_assigned_resource_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uai"]
    }
  }
  expect_failures = [var.managed_identities]
}

run "rejects_transform_without_source" {
  command = plan
  variables {
    workspace_transforms = {
      name             = "law-example-dcr"
      table_transforms = { AppMetrics = { transform_kql = "AppMetrics | where true" } }
    }
  }
  expect_failures = [var.workspace_transforms]
}

run "rejects_empty_transforms" {
  command = plan
  variables {
    workspace_transforms = {
      name             = "law-example-dcr"
      table_transforms = {}
    }
  }
  expect_failures = [var.workspace_transforms]
}

run "rejects_bad_linked_storage_type" {
  command = plan
  variables {
    linked_storage_accounts = {
      Logs = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Storage/storageAccounts/stexample"]
    }
  }
  expect_failures = [var.linked_storage_accounts]
}

run "rejects_bad_role_assignment_name" {
  command = plan
  variables {
    role_assignments = {
      contributor = {
        name                       = "not-a-guid"
        role_definition_id_or_name = "Log Analytics Contributor"
        principal_id               = "11111111-1111-1111-1111-111111111111"
      }
    }
  }
  expect_failures = [var.role_assignments]
}
