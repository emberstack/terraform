# =============================================================================
# azure-res-network-azurefirewall tests
# =============================================================================
# `mock_provider` keeps the suite offline: negative runs abort during variable
# validation, and the positive runs need a resource graph but not a real
# subscription.
#
# Caveat: mocking bypasses AzAPI's own schema checks, and cannot reproduce ARM
# reordering `zones`, so the `ignore_changes` on them is proved against a real
# plan, not here.
# =============================================================================

mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }
}

mock_provider "random" {}

variables {
  name                = "afw-example"
  resource_group_name = "rg-example"
  location            = "westeurope"
  subnet_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/AzureFirewallSubnet"
  firewall_sku_tier   = "Premium"
  firewall_policy_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/firewallPolicies/afwp-example"
  ip_configurations = {
    zz-primary = {
      public_ip_address_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-example-01"
      primary                       = true
    }
    aa-extra = {
      public_ip_address_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-example-02"
    }
  }
}

# =============================================================================
# POSITIVE
# =============================================================================

run "plans_firewall_primary_first" {
  command = plan

  assert {
    condition     = azapi_resource.this.body.properties.ipConfigurations[0].name == "zz-primary" && azapi_resource.this.body.properties.ipConfigurations[1].name == "aa-extra"
    error_message = "the primary configuration must be sent first, whatever the keys sort to"
  }
  assert {
    condition     = azapi_resource.this.body.properties.ipConfigurations[0].properties.subnet.id == var.subnet_resource_id && azapi_resource.this.body.properties.ipConfigurations[1].properties.subnet == null
    error_message = "only the primary configuration may carry the subnet"
  }
  assert {
    condition     = azapi_resource.this.body.properties.sku.name == "AZFW_VNet" && azapi_resource.this.body.properties.sku.tier == "Premium"
    error_message = "the SKU must be the virtual-network form with the configured tier"
  }
  assert {
    condition     = azapi_resource.this.body.properties.firewallPolicy.id == var.firewall_policy_id && azapi_resource.this.body.properties.managementIpConfiguration == null
    error_message = "the policy must be referenced, and no management configuration sent when unset"
  }
  assert {
    condition     = length(azapi_resource.this.body.zones) == 3 && length(azapi_resource.management_public_ip) == 0
    error_message = "zones must default to zone-redundant, and no management IP be created when unset"
  }
  assert {
    condition     = azapi_resource.this.timeouts.create == "90m"
    error_message = "the long azurerm-derived timeouts must reach the firewall"
  }
  assert {
    condition     = output.ip_configurations["aa-extra"].resource_id != null && output.management_public_ip == null
    error_message = "the outputs must evaluate"
  }
}

run "plans_management_configuration_and_public_ip" {
  command = plan

  variables {
    firewall_management_ip_configuration = {
      subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/AzureFirewallManagementSubnet"
    }
    tags = { environment = "example" }
  }

  assert {
    condition     = azapi_resource.management_public_ip[0].name == "afw-example-mgmt-pip" && azapi_resource.management_public_ip[0].tags["environment"] == "example"
    error_message = "the management IP must default its name and take the module tags"
  }
  assert {
    condition     = azapi_resource.management_public_ip[0].body.sku.name == "Standard" && length(azapi_resource.management_public_ip[0].body.zones) == 3
    error_message = "the management IP must be Standard and zone-redundant by default"
  }
  assert {
    condition     = azapi_resource.this.body.properties.managementIpConfiguration.name == "management" && azapi_resource.this.body.properties.managementIpConfiguration.properties.subnet.id == var.firewall_management_ip_configuration.subnet_resource_id
    error_message = "the management configuration must default its name and attach to its subnet"
  }
}

run "plans_non_zonal_firewall" {
  command = plan

  variables {
    firewall_zones = []
  }

  assert {
    condition     = azapi_resource.this.body.zones == null
    error_message = "a non-zonal firewall must send null zones, never an empty list"
  }
}

# =============================================================================
# NEGATIVE
# =============================================================================

run "rejects_two_primaries" {
  command = plan

  variables {
    ip_configurations = {
      a = { public_ip_address_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-a", primary = true }
      b = { public_ip_address_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-b", primary = true }
    }
  }

  expect_failures = [var.ip_configurations]
}

run "rejects_subnet_other_than_azurefirewallsubnet" {
  command = plan

  variables {
    subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/default"
  }

  expect_failures = [var.subnet_resource_id]
}

run "rejects_wrong_management_subnet" {
  command = plan

  variables {
    firewall_management_ip_configuration = {
      subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/AzureFirewallSubnet"
    }
  }

  expect_failures = [var.firewall_management_ip_configuration]
}

run "rejects_policy_id_that_is_not_a_policy" {
  command = plan

  variables {
    firewall_policy_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/azureFirewalls/afw-other"
  }

  expect_failures = [var.firewall_policy_id]
}

run "rejects_unknown_tier" {
  command = plan

  variables {
    firewall_sku_tier = "Enterprise"
  }

  expect_failures = [var.firewall_sku_tier]
}
