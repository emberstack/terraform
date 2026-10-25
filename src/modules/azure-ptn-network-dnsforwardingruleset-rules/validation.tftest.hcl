# =============================================================================
# azure-ptn-network-dnsforwardingruleset-rules tests
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

mock_provider "azapi" {}

variables {
  dns_forwarding_ruleset_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/dnsForwardingRulesets/dnsfrs-example"
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans_rules_with_defaults_and_ordered_targets" {
  command = plan

  variables {
    rules = {
      corp-onprem = {
        domain_name = "corp.example.com."
        target_dns_servers = [
          { ip_address = "10.20.0.5" },
          { ip_address = "10.20.0.4", port = 5353 },
        ]
      }
      wildcard = {
        name        = "Wildcard_Rule"
        domain_name = "."
        target_dns_servers = [
          { ip_address = "10.30.0.4" },
        ]
        enabled  = false
        metadata = { owner = "platform" }
      }
    }
  }

  assert {
    condition     = azapi_resource.this["corp-onprem"].name == "corp-onprem" && azapi_resource.this["wildcard"].name == "Wildcard_Rule"
    error_message = "the ARM name must default to the map key and honour an explicit name"
  }
  assert {
    condition     = azapi_resource.this["corp-onprem"].parent_id == var.dns_forwarding_ruleset_resource_id
    error_message = "each rule must be parented on the supplied ruleset"
  }
  assert {
    condition     = [for s in azapi_resource.this["corp-onprem"].body.properties.targetDnsServers : s.ipAddress] == ["10.20.0.5", "10.20.0.4"]
    error_message = "target servers must keep the input order, not be re-sorted"
  }
  assert {
    condition     = [for s in azapi_resource.this["corp-onprem"].body.properties.targetDnsServers : s.port] == [53, 5353]
    error_message = "port must default to 53 and honour an explicit value"
  }
  assert {
    condition     = azapi_resource.this["corp-onprem"].body.properties.forwardingRuleState == "Enabled" && azapi_resource.this["wildcard"].body.properties.forwardingRuleState == "Disabled"
    error_message = "enabled must map to forwardingRuleState Enabled/Disabled"
  }
  assert {
    condition     = azapi_resource.this["wildcard"].body.properties.metadata.owner == "platform" && azapi_resource.this["corp-onprem"].body.properties.metadata == null
    error_message = "metadata must pass through when set and stay null when not"
  }
  assert {
    condition     = output.rules["corp-onprem"].domain_name == "corp.example.com." && output.dns_forwarding_ruleset_resource_id == var.dns_forwarding_ruleset_resource_id
    error_message = "outputs must evaluate"
  }
}

# =============================================================================
# NEGATIVE — each validation must fire
# =============================================================================

run "rejects_domain_without_trailing_dot" {
  command = plan
  variables {
    rules = {
      corp = {
        domain_name        = "corp.example.com"
        target_dns_servers = [{ ip_address = "10.20.0.4" }]
      }
    }
  }
  expect_failures = [var.rules]
}

run "rejects_domain_with_more_than_34_labels" {
  command = plan
  variables {
    rules = {
      deep = {
        domain_name        = "${join(".", [for i in range(35) : "l${i}"])}."
        target_dns_servers = [{ ip_address = "10.20.0.4" }]
      }
    }
  }
  expect_failures = [var.rules]
}

run "rejects_name_starting_with_digit" {
  command = plan
  variables {
    rules = {
      corp = {
        name               = "1corp"
        domain_name        = "corp.example.com."
        target_dns_servers = [{ ip_address = "10.20.0.4" }]
      }
    }
  }
  expect_failures = [var.rules]
}

run "rejects_names_differing_only_in_case" {
  command = plan
  variables {
    rules = {
      a = {
        name               = "Corp"
        domain_name        = "corp.example.com."
        target_dns_servers = [{ ip_address = "10.20.0.4" }]
      }
      b = {
        name               = "corp"
        domain_name        = "corp2.example.com."
        target_dns_servers = [{ ip_address = "10.20.0.4" }]
      }
    }
  }
  expect_failures = [var.rules]
}

run "rejects_rule_without_targets" {
  command = plan
  variables {
    rules = {
      corp = {
        domain_name        = "corp.example.com."
        target_dns_servers = []
      }
    }
  }
  expect_failures = [var.rules]
}

run "rejects_target_with_prefix_length" {
  command = plan
  variables {
    rules = {
      corp = {
        domain_name        = "corp.example.com."
        target_dns_servers = [{ ip_address = "10.20.0.0/24" }]
      }
    }
  }
  expect_failures = [var.rules]
}

run "rejects_port_out_of_range" {
  command = plan
  variables {
    rules = {
      corp = {
        domain_name        = "corp.example.com."
        target_dns_servers = [{ ip_address = "10.20.0.4", port = 70000 }]
      }
    }
  }
  expect_failures = [var.rules]
}

run "rejects_non_ruleset_parent" {
  command = plan
  variables {
    dns_forwarding_ruleset_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/dnsResolvers/dnspr-example"
  }
  expect_failures = [var.dns_forwarding_ruleset_resource_id]
}
