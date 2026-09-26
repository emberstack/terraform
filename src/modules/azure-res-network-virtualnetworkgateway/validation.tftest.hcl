# =============================================================================
# azure-res-network-virtualnetworkgateway tests
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
  name                = "vgw-example"
  resource_group_name = "rg-example"
  location            = "westeurope"
  subnet_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/GatewaySubnet"
  sku                 = "VpnGw2AZ"
  ip_configurations = {
    primary = {
      public_ip_address_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-example-01"
    }
  }
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans_active_active_bgp_gateway" {
  command = plan

  variables {
    vpn_active_active_enabled      = true
    vpn_bgp_enabled                = true
    vpn_private_ip_address_enabled = true
    vpn_bgp_settings = {
      asn = 65515
    }
    ip_configurations = {
      primary = {
        public_ip_address_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-example-01"
        apipa_addresses               = ["169.254.21.2"]
      }
      secondary = {
        public_ip_address_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-example-02"
      }
    }
  }

  assert {
    condition     = azapi_resource.this.parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"
    error_message = "the gateway must be parented on the resource group in the provider's subscription"
  }
  assert {
    condition     = azapi_resource.this.body.properties.activeActive == true && azapi_resource.this.body.properties.enableBgp == true
    error_message = "active-active and BGP must be sent as configured"
  }
  assert {
    condition     = length(azapi_resource.this.body.properties.ipConfigurations) == 2 && azapi_resource.this.body.properties.ipConfigurations[0].name == "primary" && azapi_resource.this.body.properties.ipConfigurations[1].name == "secondary"
    error_message = "one IP configuration per map entry, named by its key"
  }
  assert {
    condition     = alltrue([for ip in azapi_resource.this.body.properties.ipConfigurations : ip.properties.subnet.id == var.subnet_resource_id && ip.properties.privateIPAllocationMethod == "Dynamic"])
    error_message = "every IP configuration must attach to GatewaySubnet with Dynamic allocation"
  }
  assert {
    condition     = azapi_resource.this.body.properties.bgpSettings.bgpPeeringAddresses[0].ipconfigurationId == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworkGateways/vgw-example/ipConfigurations/primary"
    error_message = "a BGP peering address must name its IP configuration by the gateway's own ID"
  }
  assert {
    condition     = length(azapi_resource.this.body.properties.bgpSettings.bgpPeeringAddresses) == 2
    error_message = "one BGP peering address per IP configuration, or azapi's positional pairing breaks"
  }
  assert {
    condition     = length(azapi_resource.this.body.properties.bgpSettings.bgpPeeringAddresses[0].customBgpIpAddresses) == 1 && azapi_resource.this.body.properties.bgpSettings.bgpPeeringAddresses[0].customBgpIpAddresses[0] == "169.254.21.2"
    error_message = "APIPA addresses must be sent on their own IP configuration's peering address"
  }
  assert {
    condition     = length(azapi_resource.this.body.properties.bgpSettings.bgpPeeringAddresses[1].customBgpIpAddresses) == 0
    error_message = "an IP configuration without APIPA addresses must send an empty list, not omit it"
  }
  assert {
    condition     = azapi_resource.this.body.properties.bgpSettings.asn == 65515 && azapi_resource.this.body.properties.bgpSettings.peerWeight == 0
    error_message = "BGP settings must send the ASN and the default peer weight"
  }
  assert {
    condition     = azapi_resource.this.body.properties.sku.name == "VpnGw2AZ" && azapi_resource.this.body.properties.sku.tier == "VpnGw2AZ"
    error_message = "the SKU must be sent as both name and tier"
  }
  assert {
    condition     = azapi_resource.this.body.properties.vpnGatewayGeneration == "Generation2" && azapi_resource.this.body.properties.vpnType == "RouteBased"
    error_message = "a VPN gateway must send its generation and routing type"
  }
  assert {
    condition     = azapi_resource.this.body.properties.disableIPSecReplayProtection == false && azapi_resource.this.body.properties.enablePrivateIpAddress == true
    error_message = "replay protection must be sent inverted, and private IP access as configured"
  }
  assert {
    condition     = output.ip_configurations["secondary"].public_ip_address_resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-example-02"
    error_message = "the ip_configurations output must evaluate — this is the run that catches bad attribute references"
  }
}

run "plans_active_standby_gateway_without_bgp" {
  command = plan

  assert {
    condition     = azapi_resource.this.body.properties.bgpSettings == null
    error_message = "without vpn_bgp_settings the body must carry a null bgpSettings, dropped by ignore_null_property"
  }
  assert {
    condition     = azapi_resource.this.ignore_null_property == true
    error_message = "the null bgpSettings relies on ignore_null_property"
  }
  assert {
    condition     = azapi_resource.this.body.properties.activeActive == false && length(azapi_resource.this.body.properties.ipConfigurations) == 1
    error_message = "an active-standby gateway sends one IP configuration"
  }
  assert {
    condition     = azapi_resource.this.timeouts.create == "90m" && azapi_resource.this.timeouts.delete == "120m"
    error_message = "the long azurerm-derived timeouts must reach the resource"
  }
}

run "sends_none_generation_for_expressroute" {
  command = plan

  variables {
    type = "ExpressRoute"
    sku  = "ErGw1AZ"
  }

  assert {
    condition     = azapi_resource.this.body.properties.gatewayType == "ExpressRoute" && azapi_resource.this.body.properties.vpnGatewayGeneration == "None"
    error_message = "a non-VPN gateway must send vpnGatewayGeneration None, as the REST specification requires"
  }
}

run "plans_lock_role_assignment_and_diagnostics" {
  command = plan

  variables {
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
    condition     = azapi_resource.role_assignments["readers"].body.properties.roleDefinitionId == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
    error_message = "a role name must resolve to its definition ID"
  }
  assert {
    condition     = azapi_resource.lock[0].name == "lock-vgw-example" && azapi_resource.lock[0].body.properties.level == "CanNotDelete"
    error_message = "the lock must default its name and send its level"
  }
  assert {
    condition     = azapi_resource.diagnostic_settings["workspace"].body.properties.logs[0].categoryGroup == "allLogs" && azapi_resource.diagnostic_settings["workspace"].body.properties.metrics[0].category == "AllMetrics"
    error_message = "diagnostic settings must default to allLogs and AllMetrics"
  }
}

# =============================================================================
# NEGATIVE — variable validation must reject these
# =============================================================================

run "rejects_active_active_with_one_configuration" {
  command = plan

  variables {
    vpn_active_active_enabled = true
  }

  expect_failures = [var.ip_configurations]
}

run "rejects_active_standby_with_two_configurations" {
  command = plan

  variables {
    ip_configurations = {
      primary = {
        public_ip_address_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-example-01"
      }
      secondary = {
        public_ip_address_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-example-02"
      }
    }
  }

  expect_failures = [var.ip_configurations]
}

run "rejects_subnet_other_than_gatewaysubnet" {
  command = plan

  variables {
    subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/default"
  }

  expect_failures = [var.subnet_resource_id]
}

run "rejects_unknown_sku" {
  command = plan

  variables {
    sku = "VpnGw6AZ"
  }

  expect_failures = [var.sku]
}

run "rejects_local_gateway_type" {
  command = plan

  variables {
    type = "LocalGateway"
  }

  expect_failures = [var.type]
}

run "rejects_azure_reserved_asn" {
  command = plan

  variables {
    vpn_bgp_settings = {
      asn = 65517
    }
  }

  expect_failures = [var.vpn_bgp_settings]
}

run "rejects_iana_reserved_asn" {
  command = plan

  variables {
    vpn_bgp_settings = {
      asn = 64500
    }
  }

  expect_failures = [var.vpn_bgp_settings]
}

run "rejects_apipa_address_outside_azure_range" {
  command = plan

  variables {
    vpn_bgp_settings = {}
    ip_configurations = {
      primary = {
        public_ip_address_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-example-01"
        apipa_addresses               = ["169.254.23.1"]
      }
    }
  }

  expect_failures = [var.ip_configurations]
}

run "rejects_apipa_address_without_bgp_settings" {
  command = plan

  variables {
    ip_configurations = {
      primary = {
        public_ip_address_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-example-01"
        apipa_addresses               = ["169.254.21.2"]
      }
    }
  }

  expect_failures = [var.ip_configurations]
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
