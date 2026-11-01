# =============================================================================
# azure-res-containerregistry-registry tests
# =============================================================================
# `mock_provider` keeps the suite offline: negative runs abort during variable
# validation or the registry's precondition, and the positive runs need a
# resource graph but not a real subscription.
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

  # A valid ARM ID, because an apply run leaves the registry in the shared test
  # state and parents children and role assignments on it.
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.ContainerRegistry/registries/acrexample"
    }
  }

  mock_data "azapi_resource" {
    defaults = {
      output = {
        client_id = "22222222-2222-2222-2222-222222222222"
      }
    }
  }

  mock_data "azapi_resource_list" {
    defaults = {
      output = {
        results = [
          {
            id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/7f951dda-4ed3-4680-a7ca-43fe172d538d"
            role_name = "AcrPull"
          },
        ]
      }
    }
  }
}

mock_provider "random" {}

variables {
  name                = "acrexample"
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
        adminUserEnabled                 = false
        anonymousPullEnabled             = false
        dataEndpointEnabled              = false
        networkRuleBypassAllowedForTasks = false
        networkRuleBypassOptions         = "AzureServices"
        networkRuleSet = {
          defaultAction = "Deny"
          ipRules       = []
        }
        policies = {
          azureADAuthenticationAsArmPolicy = { status = "enabled" }
          exportPolicy                     = { status = "enabled" }
          quarantinePolicy                 = { status = "disabled" }
          retentionPolicy                  = { days = 7, status = "disabled" }
          trustPolicy                      = { status = "disabled", type = "Notary" }
        }
        publicNetworkAccess = "Disabled"
        roleAssignmentMode  = "LegacyRegistryPermissions"
        zoneRedundancy      = "Enabled"
      }
      sku = { name = "Premium" }
    })
    error_message = "Defaults must be a closed Premium registry with every policy sent and no encryption block."
  }

  assert {
    condition     = length(azapi_resource.this.identity) == 0
    error_message = "No identity must be requested by default."
  }

  assert {
    condition = (
      length(azapi_resource.replications) == 0 &&
      length(azapi_resource_action.import_image) == 0 &&
      length(azapi_resource.private_endpoint) == 0 &&
      length(azapi_resource.diagnostic_settings) == 0 &&
      length(azapi_resource.lock) == 0
    )
    error_message = "No children must be created by default."
  }

  assert {
    condition     = output.role_assignments == {} && output.private_endpoints == {} && output.lock_resource_id == null
    error_message = "Outputs must evaluate with no children."
  }
}

run "standard_tier" {
  command = plan

  variables {
    sku                     = "Standard"
    zone_redundancy_enabled = false
  }

  assert {
    condition = (
      !contains(keys(azapi_resource.this.body.properties), "networkRuleSet") &&
      jsonencode(azapi_resource.this.body.properties.policies) == jsonencode({
        azureADAuthenticationAsArmPolicy = { status = "enabled" }
        exportPolicy                     = { status = "enabled" }
      })
    )
    error_message = "Below Premium, network rules and the Premium-only policies must be left out of the body."
  }
}

run "children" {
  command = apply

  variables {
    data_endpoint_enabled = true
    managed_identities = {
      system_assigned            = true
      user_assigned_resource_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uai-cmk"]
    }
    customer_managed_key = {
      key_vault_key_uri                  = "https://kv-example.vault.azure.net/keys/acr"
      user_assigned_identity_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/rg-example/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uai-cmk"
    }

    georeplications = {
      northeurope = {}
    }

    import_images = {
      seed = {
        source_registry_uri = "ghcr.io"
        source_image        = "emberstack/scratch/empty:latest"
        target_tags         = ["seed:latest"]
      }
      as_is = {
        source_registry_uri = "mcr.microsoft.com"
        source_image        = "hello-world:latest"
      }
    }

    private_endpoints = {
      default = {
        name                            = "acrexample-pe"
        private_service_connection_name = "acrexample-pe"
        subnet_resource_id              = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet/subnets/pe"
        private_dns_zone_resource_ids   = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"]
      }
    }

    diagnostic_settings = {
      sentinel = {
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/law"
        log_categories = {
          ContainerRegistryLoginEvents      = true
          ContainerRegistryRepositoryEvents = true
        }
        log_groups        = {}
        metric_categories = { AllMetrics = false }
      }
    }

    role_assignments = {
      pull = {
        role_definition_id_or_name = "AcrPull"
        principal_id               = "11111111-1111-1111-1111-111111111111"
        principal_type             = "ServicePrincipal"
      }
    }

    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition = jsonencode(azapi_resource.this.body.properties.encryption) == jsonencode({
      keyVaultProperties = {
        identity      = "22222222-2222-2222-2222-222222222222"
        keyIdentifier = "https://kv-example.vault.azure.net/keys/acr"
      }
      status = "enabled"
    })
    error_message = "Encryption must name the key and the identity's client ID."
  }

  assert {
    condition     = azapi_resource.this.identity[0].type == "SystemAssigned, UserAssigned" && azapi_resource.this.body.properties.dataEndpointEnabled == true
    error_message = "Both identity kinds and the data endpoint must be requested."
  }

  assert {
    condition = (
      jsonencode(azapi_resource_action.import_image["seed"].body) == jsonencode({
        mode       = "NoForce"
        source     = { registryUri = "ghcr.io", sourceImage = "emberstack/scratch/empty:latest" }
        targetTags = ["seed:latest"]
      }) &&
      !contains(keys(azapi_resource_action.import_image["as_is"].body), "targetTags")
    )
    error_message = "Image imports must send NoForce, and leave targetTags out when none are given."
  }

  assert {
    condition = jsonencode(azapi_resource.diagnostic_settings["sentinel"].body.properties.metrics) == jsonencode([
      { category = "AllMetrics", enabled = false, retentionPolicy = { days = 0, enabled = false } },
    ]) && length(azapi_resource.diagnostic_settings["sentinel"].body.properties.logs) == 2 && azapi_resource.diagnostic_settings["sentinel"].body.properties.logAnalyticsDestinationType == null
    error_message = "Diagnostic categories must be sent in full, disabled ones included, and no destination type."
  }

  assert {
    condition = (
      !contains(keys(azapi_resource.private_endpoint["default"].body.properties), "customNetworkInterfaceName") &&
      azapi_resource.private_endpoint["default"].body.properties.privateLinkServiceConnections[0].name == "acrexample-pe" &&
      azapi_resource.private_endpoint["default"].body.properties.privateLinkServiceConnections[0].properties.groupIds == ["registry"] &&
      azapi_resource.private_endpoint["default"].parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"
    )
    error_message = "The private endpoint must target the registry subresource from the registry's resource group."
  }

  assert {
    condition     = azapi_resource.replications["northeurope"].name == "northeurope" && azapi_resource.replications["northeurope"].body.properties.zoneRedundancy == "Enabled"
    error_message = "A replication must be named after its region."
  }

  assert {
    condition     = azapi_resource.role_assignments["pull"].body.properties.roleDefinitionId == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/7f951dda-4ed3-4680-a7ca-43fe172d538d"
    error_message = "A role name must resolve to its definition ID."
  }

  assert {
    condition     = output.private_endpoints["default"].name == "acrexample-pe" && output.lock_resource_id != null && output.georeplications["northeurope"].resource_id != null
    error_message = "Outputs must carry the endpoint, the lock and the replica."
  }
}

# =============================================================================
# NEGATIVE — variable validation and the registry precondition
# =============================================================================

run "rejects_bad_name" {
  command = plan
  variables {
    name = "acr-example"
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
    sku = "Classic"
  }
  expect_failures = [var.sku]
}

run "rejects_bad_role_assignment_mode" {
  command = plan
  variables {
    role_assignment_mode = "Abac"
  }
  expect_failures = [var.role_assignment_mode]
}

run "rejects_retention_out_of_range" {
  command = plan
  variables {
    retention_policy = { enabled = true, days = 400 }
  }
  expect_failures = [var.retention_policy]
}

run "rejects_bad_key_uri" {
  command = plan
  variables {
    managed_identities = {
      user_assigned_resource_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uai-cmk"]
    }
    customer_managed_key = {
      key_vault_key_uri                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.KeyVault/vaults/kv/keys/acr"
      user_assigned_identity_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uai-cmk"
    }
  }
  expect_failures = [var.customer_managed_key]
}

run "rejects_unattached_key_identity" {
  command = plan
  variables {
    customer_managed_key = {
      key_vault_key_uri                  = "https://kv-example.vault.azure.net/keys/acr"
      user_assigned_identity_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uai-cmk"
    }
  }
  expect_failures = [var.customer_managed_key]
}

run "rejects_home_region_replica" {
  command = plan
  variables {
    georeplications = {
      westeurope = {}
    }
  }
  expect_failures = [var.georeplications]
}

run "rejects_premium_features_below_premium" {
  command = plan
  variables {
    sku = "Standard"
    private_endpoints = {
      default = {
        subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet/subnets/pe"
      }
    }
  }
  expect_failures = [azapi_resource.this]
}

run "rejects_bad_network_rule_action" {
  command = plan
  variables {
    network_rule_set = { default_action = "Block" }
  }
  expect_failures = [var.network_rule_set]
}

run "rejects_two_diagnostic_destinations" {
  command = plan
  variables {
    diagnostic_settings = {
      sentinel = {
        workspace_resource_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/law"
        storage_account_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Storage/storageAccounts/stexample"
      }
    }
  }
  expect_failures = [var.diagnostic_settings]
}

run "rejects_bad_role_assignment_name" {
  command = plan
  variables {
    role_assignments = {
      pull = {
        name                       = "not-a-guid"
        role_definition_id_or_name = "AcrPull"
        principal_id               = "11111111-1111-1111-1111-111111111111"
      }
    }
  }
  expect_failures = [var.role_assignments]
}

run "rejects_bad_lock_kind" {
  command = plan
  variables {
    lock = { kind = "DoNotDelete" }
  }
  expect_failures = [var.lock]
}
