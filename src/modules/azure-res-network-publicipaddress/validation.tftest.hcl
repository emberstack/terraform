# =============================================================================
# azure-res-network-publicipaddress tests
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

  # A valid ARM ID, because an apply run leaves this address in the shared test
  # state and a later run parents role assignments on it.
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-example"
      output = {
        ip_address = "203.0.113.10"
        fqdn       = "pip-example.westeurope.cloudapp.azure.com"
      }
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
  name                = "pip-example"
  resource_group_name = "rg-example"
  location            = "westeurope"
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans_default_address" {
  command = plan

  assert {
    condition     = azapi_resource.this.body.sku.name == "Standard" && azapi_resource.this.body.sku.tier == "Regional"
    error_message = "the SKU must default to Standard, Regional"
  }
  assert {
    condition     = azapi_resource.this.body.zones == tolist(["1", "2", "3"])
    error_message = "the address must default to zone-redundant"
  }
  assert {
    condition = (
      azapi_resource.this.body.properties.publicIPAllocationMethod == "Static" &&
      azapi_resource.this.body.properties.publicIPAddressVersion == "IPv4" &&
      azapi_resource.this.body.properties.idleTimeoutInMinutes == 4 &&
      length(azapi_resource.this.body.properties.ipTags) == 0 &&
      azapi_resource.this.body.properties.ddosSettings.protectionMode == "VirtualNetworkInherited"
    )
    error_message = "the echoed properties must be sent at Azure's defaults"
  }
  assert {
    condition     = azapi_resource.this.body.properties.dnsSettings == null && azapi_resource.this.body.properties.publicIPPrefix == null && azapi_resource.this.body.properties.ddosSettings.ddosProtectionPlan == null
    error_message = "unused optional objects must be sent as null"
  }
}

run "plans_prefix_address_with_dns_label" {
  command = apply

  variables {
    public_ip_prefix_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPPrefixes/ippre-example"
    domain_name_label            = "pip-example"
    ip_tags                      = { RoutingPreference = "Internet" }
    zones                        = []
  }

  assert {
    condition     = azapi_resource.this.body.properties.publicIPPrefix.id == var.public_ip_prefix_resource_id
    error_message = "the prefix must pass through"
  }
  assert {
    condition     = azapi_resource.this.body.properties.dnsSettings.domainNameLabel == "pip-example" && azapi_resource.this.body.properties.dnsSettings.domainNameLabelScope == null
    error_message = "the DNS label must pass through, with no scope unless asked for"
  }
  assert {
    condition     = azapi_resource.this.body.properties.ipTags[0].ipTagType == "RoutingPreference" && azapi_resource.this.body.properties.ipTags[0].tag == "Internet"
    error_message = "IP tags must be sent as ipTagType/tag objects"
  }
  assert {
    condition     = azapi_resource.this.body.zones == null
    error_message = "a non-zonal address must send no zones"
  }
  assert {
    condition     = output.ip_address == "203.0.113.10" && output.fqdn == "pip-example.westeurope.cloudapp.azure.com"
    error_message = "ip_address and fqdn must come from the exported response values"
  }
}

run "plans_role_assignments" {
  command = plan

  variables {
    role_assignments = {
      netcontrib = {
        role_definition_id_or_name = "Network Contributor"
        principal_id               = "11111111-1111-1111-1111-111111111111"
        principal_type             = "Group"
      }
    }
  }

  assert {
    condition     = endswith(azapi_resource.role_assignments["netcontrib"].body.properties.roleDefinitionId, "/4d97b98b-1d4f-4787-a291-c67834d212e7")
    error_message = "a role name must resolve to its definition ID"
  }
}

# =============================================================================
# NEGATIVE — each validation must fire
# =============================================================================

run "rejects_name_ending_in_hyphen" {
  command = plan
  variables {
    name = "pip-"
  }
  expect_failures = [var.name]
}

run "rejects_basic_sku" {
  command = plan
  variables {
    sku = "Basic"
  }
  expect_failures = [var.sku]
}

run "rejects_unknown_tier" {
  command = plan
  variables {
    sku_tier = "Local"
  }
  expect_failures = [var.sku_tier]
}

run "rejects_zonal_global_address" {
  command = plan
  variables {
    sku_tier = "Global"
  }
  expect_failures = [var.zones]
}

run "rejects_zone_4" {
  command = plan
  variables {
    zones = ["4"]
  }
  expect_failures = [var.zones]
}

run "rejects_non_prefix_id" {
  command = plan
  variables {
    public_ip_prefix_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-other"
  }
  expect_failures = [var.public_ip_prefix_resource_id]
}

run "rejects_idle_timeout_out_of_range" {
  command = plan
  variables {
    idle_timeout_in_minutes = 3
  }
  expect_failures = [var.idle_timeout_in_minutes]
}

run "rejects_uppercase_dns_label" {
  command = plan
  variables {
    domain_name_label = "Pip-Example"
  }
  expect_failures = [var.domain_name_label]
}

run "rejects_label_scope_without_label" {
  command = plan
  variables {
    domain_name_label_scope = "TenantReuse"
  }
  expect_failures = [var.domain_name_label_scope]
}

run "rejects_unknown_label_scope" {
  command = plan
  variables {
    domain_name_label       = "pip-example"
    domain_name_label_scope = "GlobalReuse"
  }
  expect_failures = [var.domain_name_label_scope]
}

run "rejects_ddos_plan_without_enabled_mode" {
  command = plan
  variables {
    ddos_protection_plan_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/ddosProtectionPlans/ddos-example"
  }
  expect_failures = [var.ddos_protection_plan_resource_id]
}

run "rejects_ipv5" {
  command = plan
  variables {
    ip_version = "IPv5"
  }
  expect_failures = [var.ip_version]
}
