# =============================================================================
# azure-res-network-bastionhost tests
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
  name                = "bas-example"
  resource_group_name = "rg-example"
  location            = "westeurope"
  subnet_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/AzureBastionSubnet"
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans_basic_bastion_with_defaults" {
  command = plan

  assert {
    condition     = azapi_resource.this.body.sku.name == "Basic" && azapi_resource.this.body.properties.scaleUnits == 2
    error_message = "the SKU must default to Basic at 2 scale units"
  }
  assert {
    condition = alltrue([
      for flag in ["disableCopyPaste", "enableFileCopy", "enableIpConnect", "enableKerberos", "enableSessionRecording", "enableShareableLink", "enableTunneling"] :
      azapi_resource.this.body.properties[flag] == null
    ])
    error_message = "every feature flag that is off must be sent as null, matching ARM's omitted key"
  }
  assert {
    condition     = azapi_resource.this.body.zones == null
    error_message = "a non-zonal host must send no zones"
  }
  assert {
    condition     = azapi_resource.public_ip.name == "bas-example-pip" && azapi_resource.public_ip.body.zones == tolist(["1", "2", "3"])
    error_message = "the public IP must default to <name>-pip, zone-redundant"
  }
  assert {
    condition     = azapi_resource.public_ip.body.properties.idleTimeoutInMinutes == 4 && azapi_resource.public_ip.body.properties.publicIPAllocationMethod == "Static"
    error_message = "the public IP must be static at Azure's default idle timeout"
  }
  assert {
    condition     = azapi_resource.this.body.properties.ipConfigurations[0].id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/bastionHosts/bas-example/bastionHostIpConfigurations/ipconfig"
    error_message = "the IP configuration must carry the ID ARM echoes for it"
  }
  assert {
    condition     = azapi_resource.this.body.properties.ipConfigurations[0].properties.subnet.id == var.subnet_resource_id
    error_message = "the IP configuration must reference the supplied subnet"
  }
  assert {
    condition     = length(azapi_resource.role_assignments) == 0 && output.public_ip.name == "bas-example-pip" && output.resource_group_name == "rg-example"
    error_message = "outputs must evaluate, with no role assignments unless asked for"
  }
}

run "plans_standard_bastion_with_features_and_roles" {
  command = plan

  variables {
    sku                    = "Standard"
    scale_units            = 4
    copy_paste_enabled     = false
    file_copy_enabled      = true
    ip_connect_enabled     = true
    kerberos_enabled       = true
    shareable_link_enabled = true
    tunneling_enabled      = true
    zones                  = ["1", "2"]
    public_ip_config = {
      name                    = "pip-custom"
      zones                   = []
      idle_timeout_in_minutes = 10
    }
    role_assignments = {
      reader = {
        role_definition_id_or_name = "Reader"
        principal_id               = "11111111-1111-1111-1111-111111111111"
        principal_type             = "Group"
        description                = "Reader on the bastion"
      }
    }
  }

  assert {
    condition = (
      azapi_resource.this.body.properties.disableCopyPaste == true &&
      azapi_resource.this.body.properties.enableFileCopy == true &&
      azapi_resource.this.body.properties.enableIpConnect == true &&
      azapi_resource.this.body.properties.enableKerberos == true &&
      azapi_resource.this.body.properties.enableShareableLink == true &&
      azapi_resource.this.body.properties.enableTunneling == true &&
      azapi_resource.this.body.properties.enableSessionRecording == null
    )
    error_message = "enabled features must be sent as true, and copy/paste off as disableCopyPaste = true"
  }
  assert {
    condition     = azapi_resource.this.body.properties.scaleUnits == 4 && azapi_resource.this.body.zones == tolist(["1", "2"])
    error_message = "scale units and zones must pass through"
  }
  assert {
    condition     = azapi_resource.public_ip.name == "pip-custom" && azapi_resource.public_ip.body.zones == null && azapi_resource.public_ip.body.properties.idleTimeoutInMinutes == 10
    error_message = "the public IP config must pass through, with [] sending no zones"
  }
  assert {
    condition     = endswith(azapi_resource.role_assignments["reader"].body.properties.roleDefinitionId, "/acdd72a7-3385-48ef-bd42-f606fba81ae7")
    error_message = "a role name must resolve to its definition ID"
  }
  assert {
    condition     = output.role_assignments["reader"].principal_id == "11111111-1111-1111-1111-111111111111"
    error_message = "outputs must evaluate"
  }
}

# =============================================================================
# NEGATIVE — each validation must fire
# =============================================================================

run "rejects_name_ending_in_hyphen" {
  command = plan
  variables {
    name = "bas-"
  }
  expect_failures = [var.name]
}

run "rejects_other_subnet" {
  command = plan
  variables {
    subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-app"
  }
  expect_failures = [var.subnet_resource_id]
}

run "rejects_developer_sku" {
  command = plan
  variables {
    sku = "Developer"
  }
  expect_failures = [var.sku]
}

run "rejects_scale_units_above_50" {
  command = plan
  variables {
    sku         = "Standard"
    scale_units = 51
  }
  expect_failures = [var.scale_units]
}

run "rejects_scaling_on_basic" {
  command = plan
  variables {
    scale_units = 3
  }
  expect_failures = [var.scale_units]
}

run "rejects_tunneling_on_basic" {
  command = plan
  variables {
    tunneling_enabled = true
  }
  expect_failures = [var.tunneling_enabled]
}

run "rejects_file_copy_on_basic" {
  command = plan
  variables {
    file_copy_enabled = true
  }
  expect_failures = [var.file_copy_enabled]
}

run "rejects_ip_connect_on_basic" {
  command = plan
  variables {
    ip_connect_enabled = true
  }
  expect_failures = [var.ip_connect_enabled]
}

run "rejects_shareable_link_on_basic" {
  command = plan
  variables {
    shareable_link_enabled = true
  }
  expect_failures = [var.shareable_link_enabled]
}

run "rejects_disabling_copy_paste_on_basic" {
  command = plan
  variables {
    copy_paste_enabled = false
  }
  expect_failures = [var.copy_paste_enabled]
}

run "rejects_session_recording_on_standard" {
  command = plan
  variables {
    sku                       = "Standard"
    session_recording_enabled = true
  }
  expect_failures = [var.session_recording_enabled]
}

run "rejects_zone_4" {
  command = plan
  variables {
    zones = ["4"]
  }
  expect_failures = [var.zones]
}

run "rejects_public_ip_idle_timeout_out_of_range" {
  command = plan
  variables {
    public_ip_config = {
      idle_timeout_in_minutes = 31
    }
  }
  expect_failures = [var.public_ip_config]
}

run "rejects_ddos_plan_without_enabled_mode" {
  command = plan
  variables {
    public_ip_config = {
      ddos_protection_plan_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/ddosProtectionPlans/ddos-example"
    }
  }
  expect_failures = [var.public_ip_config]
}

run "rejects_uppercase_role_assignment_name" {
  command = plan
  variables {
    role_assignments = {
      reader = {
        name                       = "11111111-1111-1111-1111-11111111111A"
        role_definition_id_or_name = "Reader"
        principal_id               = "11111111-1111-1111-1111-111111111111"
      }
    }
  }
  expect_failures = [var.role_assignments]
}
