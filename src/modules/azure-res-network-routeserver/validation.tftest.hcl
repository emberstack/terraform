# =============================================================================
# azure-res-network-routeserver tests
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
  name                = "rs-example"
  resource_group_name = "rg-example"
  location            = "westeurope"
  subnet_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/RouteServerSubnet"
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans_route_server_with_defaults" {
  command = plan

  assert {
    condition     = azapi_resource.this.parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"
    error_message = "the route server must be parented on the resource group in the provider's subscription"
  }
  assert {
    condition     = azapi_resource.this.body.properties.sku == "Standard" && azapi_resource.this.body.properties.hubRoutingPreference == "ExpressRoute"
    error_message = "the hub must send the Standard SKU and the default routing preference"
  }
  assert {
    condition     = azapi_resource.this.body.properties.allowBranchToBranchTraffic == false && azapi_resource.this.body.properties.virtualRouterAutoScaleConfiguration.minCapacity == 2
    error_message = "branch-to-branch and capacity must be sent explicitly with their defaults"
  }
  assert {
    condition     = azapi_resource.ip_configuration.name == "ipConfig1" && azapi_resource.ip_configuration.body.properties.subnet.id == var.subnet_resource_id
    error_message = "the IP configuration must default its name and attach to RouteServerSubnet"
  }
  assert {
    condition     = azapi_resource.public_ip.name == "rs-example-pip" && azapi_resource.public_ip.body.sku.name == "Standard" && azapi_resource.public_ip.body.sku.tier == "Regional"
    error_message = "the public IP must default its name and send the Standard, Regional SKU"
  }
  assert {
    condition     = length(azapi_resource.public_ip.body.zones) == 3 && azapi_resource.public_ip.body.properties.publicIPAllocationMethod == "Static"
    error_message = "the public IP must default to zone-redundant and static"
  }
  assert {
    condition     = azapi_resource.public_ip.body.properties.ddosSettings.protectionMode == "VirtualNetworkInherited" && azapi_resource.public_ip.body.properties.ddosSettings.ddosProtectionPlan == null
    error_message = "the DDoS mode must be sent explicitly, and the plan dropped when unused"
  }
  assert {
    condition     = azapi_resource.this.timeouts.create == "60m" && azapi_resource.ip_configuration.timeouts.create == "60m"
    error_message = "the hub and its IP configuration must both carry the long timeouts"
  }
  assert {
    condition     = output.name == "rs-example" && output.public_ip.name == "rs-example-pip"
    error_message = "the outputs must evaluate — this is the run that catches bad attribute references"
  }
}

run "plans_non_zonal_public_ip" {
  command = plan

  variables {
    routeserver_public_ip_config = {
      name  = "pip-example"
      zones = []
    }
    tags = {
      environment = "example"
    }
  }

  assert {
    condition     = azapi_resource.public_ip.body.zones == null
    error_message = "a non-zonal public IP must send null zones, dropped by ignore_null_property, never an empty list"
  }
  assert {
    condition     = azapi_resource.public_ip.name == "pip-example" && azapi_resource.public_ip.tags["environment"] == "example"
    error_message = "the public IP must take the supplied name and fall back to the module tags"
  }
}

run "plans_lock_role_assignment_and_diagnostics" {
  command = plan

  variables {
    enable_branch_to_branch = true
    lock = {
      kind = "CanNotDelete"
    }
    role_assignments = {
      readers = {
        role_definition_id_or_name = "Reader"
        principal_id               = "11111111-1111-1111-1111-111111111111"
        principal_type             = "Group"
      }
    }
    diagnostic_settings = {
      workspace = {
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/law-example"
      }
    }
  }

  assert {
    condition     = azapi_resource.this.body.properties.allowBranchToBranchTraffic == true
    error_message = "branch-to-branch must be sent as configured"
  }
  assert {
    condition     = azapi_resource.role_assignments["readers"].body.properties.roleDefinitionId == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
    error_message = "a role name must resolve to its definition ID"
  }
  assert {
    condition     = azapi_resource.lock[0].name == "lock-rs-example" && azapi_resource.lock[0].body.properties.level == "CanNotDelete"
    error_message = "the lock must default its name and send its level"
  }
  assert {
    condition     = length(azapi_resource.diagnostic_settings["workspace"].body.properties.logs) == 0 && azapi_resource.diagnostic_settings["workspace"].body.properties.metrics[0].category == "AllMetrics"
    error_message = "a route server's diagnostic setting sends no logs and defaults to AllMetrics"
  }
}

# =============================================================================
# NEGATIVE — variable validation must reject these
# =============================================================================

run "rejects_subnet_other_than_routeserversubnet" {
  command = plan

  variables {
    subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/GatewaySubnet"
  }

  expect_failures = [var.subnet_resource_id]
}

run "rejects_unknown_routing_preference" {
  command = plan

  variables {
    hub_routing_preference = "Shortest"
  }

  expect_failures = [var.hub_routing_preference]
}

run "rejects_unknown_zone" {
  command = plan

  variables {
    routeserver_public_ip_config = {
      zones = ["4"]
    }
  }

  expect_failures = [var.routeserver_public_ip_config]
}

run "rejects_ddos_plan_without_enabled_mode" {
  command = plan

  variables {
    routeserver_public_ip_config = {
      ddos_protection_plan_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/ddosProtectionPlans/ddos-example"
    }
  }

  expect_failures = [var.routeserver_public_ip_config]
}

run "rejects_fractional_capacity" {
  command = plan

  variables {
    routing_infrastructure_units = 2.5
  }

  expect_failures = [var.routing_infrastructure_units]
}

run "rejects_diagnostic_setting_without_destination" {
  command = plan

  variables {
    diagnostic_settings = {
      nowhere = {}
    }
  }

  expect_failures = [var.diagnostic_settings]
}

run "rejects_resource_group_id" {
  command = plan

  variables {
    resource_group_name = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"
  }

  expect_failures = [var.resource_group_name]
}
