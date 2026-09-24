# =============================================================================
# azure-ptn-network-routetable-routes tests
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
  route_table_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/routeTables/rt-example"
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans_appliance_and_service_tag_routes" {
  command = plan

  variables {
    routes = {
      default = {
        name                   = "default-to-firewall"
        address_prefix         = "0.0.0.0/0"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = "10.0.0.4"
      }
      monitor = {
        name           = "azure-monitor-direct"
        address_prefix = "AzureMonitor"
        next_hop_type  = "Internet"
      }
    }
  }

  assert {
    condition     = azapi_resource.this["default"].body.properties.nextHopIpAddress == "10.0.0.4"
    error_message = "an appliance route must send its next hop address"
  }
  assert {
    condition     = azapi_resource.this["monitor"].body.properties.nextHopIpAddress == null
    error_message = "a non-appliance route must send a null next hop address, not omit or invent one"
  }
  assert {
    condition     = azapi_resource.this["default"].parent_id == var.route_table_resource_id
    error_message = "every route must be parented on the supplied table"
  }
  assert {
    condition     = azapi_resource.this["monitor"].locks == tolist([var.route_table_resource_id])
    error_message = "every route must lock the route table"
  }
  assert {
    condition     = output.routes["default"].name == "default-to-firewall" && output.routes["monitor"].address_prefix == "AzureMonitor"
    error_message = "the routes output must evaluate — this is the run that catches bad attribute references"
  }
}

run "plans_ipv6_appliance_route" {
  command = plan

  variables {
    routes = {
      v6 = {
        name                   = "v6-default_"
        address_prefix         = "::/0"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = "fd00::4"
      }
    }
  }

  assert {
    condition     = output.routes["v6"].next_hop_in_ip_address == "fd00::4"
    error_message = "an IPv6 next hop and a name ending in an underscore must both be accepted"
  }
}

run "plans_empty_map" {
  command = plan

  assert {
    condition     = length(output.routes) == 0
    error_message = "an empty map must plan nothing"
  }
}

# =============================================================================
# NEGATIVE — route_table_resource_id
# =============================================================================

run "rejects_non_route_table_parent" {
  command = plan

  variables {
    route_table_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example"
  }

  expect_failures = [var.route_table_resource_id]
}

# =============================================================================
# NEGATIVE — routes
# =============================================================================

run "rejects_name_ending_in_period" {
  command = plan

  variables {
    routes = {
      bad = { name = "bad.", address_prefix = "10.0.0.0/8", next_hop_type = "None" }
    }
  }

  expect_failures = [var.routes]
}

run "rejects_names_differing_only_in_case" {
  command = plan

  variables {
    routes = {
      a = { name = "spoke", address_prefix = "10.1.0.0/16", next_hop_type = "None" }
      b = { name = "SPOKE", address_prefix = "10.2.0.0/16", next_hop_type = "None" }
    }
  }

  expect_failures = [var.routes]
}

run "rejects_malformed_cidr" {
  command = plan

  variables {
    routes = {
      bad = { name = "bad", address_prefix = "10.0.0.0/33", next_hop_type = "None" }
    }
  }

  expect_failures = [var.routes]
}

run "rejects_prefix_with_whitespace" {
  command = plan

  variables {
    routes = {
      bad = { name = "bad", address_prefix = "Azure Monitor", next_hop_type = "Internet" }
    }
  }

  expect_failures = [var.routes]
}

run "rejects_ecmp_next_hop_type" {
  command = plan

  variables {
    routes = {
      bad = { name = "bad", address_prefix = "10.0.0.0/8", next_hop_type = "VirtualApplianceEcmp" }
    }
  }

  expect_failures = [var.routes]
}

run "rejects_appliance_without_address" {
  command = plan

  variables {
    routes = {
      bad = { name = "bad", address_prefix = "10.0.0.0/8", next_hop_type = "VirtualAppliance" }
    }
  }

  expect_failures = [var.routes]
}

run "rejects_address_on_non_appliance" {
  command = plan

  variables {
    routes = {
      bad = { name = "bad", address_prefix = "10.0.0.0/8", next_hop_type = "Internet", next_hop_in_ip_address = "10.0.0.4" }
    }
  }

  expect_failures = [var.routes]
}

run "rejects_address_with_prefix_length" {
  command = plan

  variables {
    routes = {
      bad = { name = "bad", address_prefix = "10.0.0.0/8", next_hop_type = "VirtualAppliance", next_hop_in_ip_address = "10.0.0.4/32" }
    }
  }

  expect_failures = [var.routes]
}

# =============================================================================
# NEGATIVE — retry
# =============================================================================

run "rejects_retry_without_patterns" {
  command = plan

  variables {
    retry = { error_message_regex = [] }
  }

  expect_failures = [var.retry]
}

run "rejects_invalid_retry_pattern" {
  command = plan

  variables {
    retry = { error_message_regex = ["(unclosed"] }
  }

  expect_failures = [var.retry]
}
