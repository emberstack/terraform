# =============================================================================
# azure-res-network-firewallpolicy tests
# =============================================================================
# `mock_provider` keeps the suite offline: negative runs abort during variable
# validation, and the positive runs need a resource graph but not a real
# subscription.
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
}

mock_provider "random" {}

variables {
  name                = "afwp-example"
  resource_group_name = "rg-example"
  location            = "westeurope"
}

# =============================================================================
# POSITIVE
# =============================================================================

run "plans_standard_policy_with_defaults" {
  command = plan

  assert {
    condition     = azapi_resource.this.parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"
    error_message = "the policy must be parented on the resource group in the provider's subscription"
  }
  assert {
    condition     = azapi_resource.this.body.properties.sku.tier == "Standard" && azapi_resource.this.body.properties.threatIntelMode == "Alert"
    error_message = "tier and threat intelligence mode must be sent with their defaults"
  }
  assert {
    condition     = azapi_resource.this.body.properties.intrusionDetection == null && azapi_resource.this.body.properties.dnsSettings == null && azapi_resource.this.body.properties.snat == null && azapi_resource.this.body.properties.basePolicy == null
    error_message = "unset blocks must be null, dropped by ignore_null_property"
  }
  assert {
    condition     = output.name == "afwp-example"
    error_message = "the outputs must evaluate"
  }
}

run "plans_premium_policy_with_idps_dns_and_snat" {
  command = plan

  variables {
    firewall_policy_sku                      = "Premium"
    firewall_policy_threat_intelligence_mode = "Deny"
    firewall_policy_intrusion_detection = {
      mode = "Deny"
    }
    firewall_policy_dns = {
      proxy_enabled = true
      servers       = ["10.0.0.4"]
    }
    firewall_policy_private_ip_ranges = ["IANAPrivateRanges", "203.0.113.0/24"]
  }

  assert {
    condition     = azapi_resource.this.body.properties.intrusionDetection.mode == "Deny"
    error_message = "the IDPS mode must be sent"
  }
  assert {
    condition = (
      length(azapi_resource.this.body.properties.intrusionDetection.configuration.bypassTrafficSettings) == 0 &&
      length(azapi_resource.this.body.properties.intrusionDetection.configuration.privateRanges) == 0 &&
      length(azapi_resource.this.body.properties.intrusionDetection.configuration.signatureOverrides) == 0
    )
    error_message = "the IDPS lists must be sent empty rather than left out"
  }
  assert {
    condition     = azapi_resource.this.body.properties.dnsSettings.enableProxy == true && azapi_resource.this.body.properties.dnsSettings.servers[0] == "10.0.0.4"
    error_message = "DNS settings must be sent as configured"
  }
  assert {
    condition     = azapi_resource.this.body.properties.snat.privateRanges[0] == "IANAPrivateRanges" && length(azapi_resource.this.body.properties.snat.privateRanges) == 2
    error_message = "SNAT private ranges must be sent in the order given"
  }
}

run "plans_idps_bypass_and_signature_override" {
  command = plan

  variables {
    firewall_policy_sku = "Premium"
    firewall_policy_intrusion_detection = {
      mode                = "Alert"
      signature_overrides = { "2024897" = "Off" }
      traffic_bypass = [
        {
          name              = "backup"
          protocol          = "TCP"
          source_addresses  = ["10.0.1.0/24"]
          destination_ports = ["443"]
        },
      ]
    }
  }

  assert {
    condition     = azapi_resource.this.body.properties.intrusionDetection.configuration.signatureOverrides[0].id == "2024897" && azapi_resource.this.body.properties.intrusionDetection.configuration.signatureOverrides[0].mode == "Off"
    error_message = "signature overrides must be sent as id/mode pairs"
  }
  assert {
    condition     = azapi_resource.this.body.properties.intrusionDetection.configuration.bypassTrafficSettings[0].name == "backup" && azapi_resource.this.body.properties.intrusionDetection.configuration.bypassTrafficSettings[0].destinationIpGroups == null
    error_message = "a bypass must send its fields, with unset ones null"
  }
}

# =============================================================================
# NEGATIVE
# =============================================================================

run "rejects_idps_below_premium" {
  command = plan

  variables {
    firewall_policy_intrusion_detection = {
      mode = "Deny"
    }
  }

  expect_failures = [var.firewall_policy_intrusion_detection]
}

run "rejects_unknown_threat_intelligence_mode" {
  command = plan

  variables {
    firewall_policy_threat_intelligence_mode = "Block"
  }

  expect_failures = [var.firewall_policy_threat_intelligence_mode]
}

run "rejects_unknown_bypass_protocol" {
  command = plan

  variables {
    firewall_policy_sku = "Premium"
    firewall_policy_intrusion_detection = {
      mode           = "Deny"
      traffic_bypass = [{ name = "x", protocol = "SCTP" }]
    }
  }

  expect_failures = [var.firewall_policy_intrusion_detection]
}

run "rejects_base_policy_that_is_not_a_policy" {
  command = plan

  variables {
    firewall_policy_base_policy_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/azureFirewalls/afw-example"
  }

  expect_failures = [var.firewall_policy_base_policy_id]
}
