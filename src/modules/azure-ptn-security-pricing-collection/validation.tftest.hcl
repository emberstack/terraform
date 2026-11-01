# =============================================================================
# azure-ptn-security-pricing-collection tests
# =============================================================================
# `mock_provider` keeps the suite offline: negative runs abort during variable
# validation or a precondition, and the positive runs need a resource graph but
# not a real subscription.
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
        accounts = [
          { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/stblob", name = "stblob", kind = "StorageV2" },
          { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/stfiles", name = "stfiles", kind = "FileStorage" },
          { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/stlegacy", name = "stlegacy", kind = "Storage" },
        ]
      }
    }
  }
}

variables {
  pricings = {
    CloudPosture = {
      extensions = [
        { name = "SensitiveDataDiscovery" },
        { name = "AgentlessVmScanning", additional_properties = { ExclusionTags = "[]" } },
        { name = "ServerlessContainers", enabled = false },
      ]
    }
    KeyVaults       = { sub_plan = "PerKeyVault" }
    Discovery       = {}
    StorageAccounts = { sub_plan = "DefenderForStorageV2" }
    Dns             = { tier = "Free" }
  }
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans" {
  command = plan

  assert {
    condition = jsonencode(azapi_resource.this["CloudPosture"].body) == jsonencode({
      properties = {
        extensions = [
          { isEnabled = "True", name = "SensitiveDataDiscovery" },
          { additionalExtensionProperties = { ExclusionTags = "[]" }, isEnabled = "True", name = "AgentlessVmScanning" },
          { isEnabled = "False", name = "ServerlessContainers" },
        ]
        pricingTier = "Standard"
      }
    })
    error_message = "Extensions must be sent in the caller's order, disabled ones included, with properties only where given."
  }

  assert {
    condition = (
      jsonencode(azapi_resource.this["KeyVaults"].body) == jsonencode({ properties = { pricingTier = "Standard", subPlan = "PerKeyVault" } }) &&
      jsonencode(azapi_resource.this["Discovery"].body) == jsonencode({ properties = { pricingTier = "Standard" } }) &&
      jsonencode(azapi_resource.this["Dns"].body) == jsonencode({ properties = { pricingTier = "Free" } })
    )
    error_message = "A plan without a sub-plan or extensions must leave both out of the body."
  }

  assert {
    condition = alltrue([
      for pricing in azapi_resource.this :
      pricing.parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000" &&
      jsonencode(pricing.locks) == jsonencode(["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Security/pricings"])
    ])
    error_message = "Every plan must sit on the provider's subscription and take the same lock."
  }

  assert {
    condition     = length(azapi_resource.malware_scan_results) == 0 && output.malware_scan_results == {}
    error_message = "No malware scan results setting must exist by default."
  }

  assert {
    condition     = output.pricings["KeyVaults"].sub_plan == "PerKeyVault" && output.pricings["Dns"].tier == "Free"
    error_message = "Outputs must carry tier and sub-plan."
  }
}

run "malware_scan_results" {
  command = plan

  variables {
    malware_scan_results = {
      name                  = "sentinel"
      workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/law"
    }
  }

  assert {
    condition     = keys(azapi_resource.malware_scan_results) == ["stblob"]
    error_message = "Only blob-capable accounts must get a setting: FileStorage and legacy v1 accounts are skipped."
  }

  assert {
    condition = (
      azapi_resource.malware_scan_results["stblob"].parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/stblob/providers/Microsoft.Security/defenderForStorageSettings/current" &&
      jsonencode(azapi_resource.malware_scan_results["stblob"].body.properties.logs) == jsonencode([
        { category = "ScanResults", categoryGroup = null, enabled = true, retentionPolicy = { days = 0, enabled = false } },
      ]) &&
      azapi_resource.malware_scan_results["stblob"].body.properties.metrics == []
    )
    error_message = "The setting must sit on the account's Defender for Storage extension and ship ScanResults only."
  }
}

# =============================================================================
# NEGATIVE — variable validation and preconditions
# =============================================================================

run "rejects_bad_plan_name" {
  command = plan
  variables {
    pricings = { "Virtual Machines" = {} }
  }
  expect_failures = [var.pricings]
}

run "rejects_bad_tier" {
  command = plan
  variables {
    pricings = { Arm = { tier = "Premium" } }
  }
  expect_failures = [var.pricings]
}

run "rejects_free_with_sub_plan" {
  command = plan
  variables {
    pricings = { Arm = { tier = "Free", sub_plan = "PerSubscription" } }
  }
  expect_failures = [var.pricings]
}

run "rejects_duplicate_extension" {
  command = plan
  variables {
    pricings = {
      Containers = {
        extensions = [{ name = "ContainerSensor" }, { name = "ContainerSensor", enabled = false }]
      }
    }
  }
  expect_failures = [var.pricings]
}

run "rejects_scan_results_without_storage_plan" {
  command = plan
  variables {
    pricings = { StorageAccounts = { tier = "Free" } }
    malware_scan_results = {
      name                  = "sentinel"
      workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/law"
    }
  }
  expect_failures = [azapi_resource.malware_scan_results]
}
