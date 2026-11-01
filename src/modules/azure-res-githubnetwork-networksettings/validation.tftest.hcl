# =============================================================================
# azure-res-githubnetwork-networksettings tests
# =============================================================================
# `mock_provider` keeps the suite offline: negative runs abort during variable
# validation, and the positive run needs a resource graph but not a real
# subscription.
#
# Caveat: mocking bypasses AzAPI's own schema checks, so the positive run cannot
# confirm ARM accepts the body. The variable validation blocks are the guard.
# =============================================================================

mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  name                = "runners"
  resource_group_name = "rg-example"
  location            = "northeurope"
  subnet_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/runners"
  business_id         = "123456"
  tags                = { environment = "example" }
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans" {
  command = plan

  assert {
    condition = jsonencode(azapi_resource.this.body) == jsonencode({
      properties = {
        businessId = "123456"
        subnetId   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/runners"
      }
    })
    error_message = "The body must carry exactly businessId and subnetId."
  }

  assert {
    condition     = azapi_resource.this.parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"
    error_message = "The resource group must resolve in the provider's subscription."
  }

  assert {
    condition     = output.github_id == null
    error_message = "github_id must be null until GitHub has tagged the resource."
  }
}

# =============================================================================
# NEGATIVE — variable validation must reject bad input
# =============================================================================

run "rejects_vnet_id_as_subnet" {
  command = plan

  variables {
    subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example"
  }

  expect_failures = [var.subnet_resource_id]
}

run "rejects_org_login_as_business_id" {
  command = plan

  variables {
    business_id = "example-org"
  }

  expect_failures = [var.business_id]
}

run "rejects_resource_group_id" {
  command = plan

  variables {
    resource_group_name = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"
  }

  expect_failures = [var.resource_group_name]
}
