# =============================================================================
# azure-ptn-network-firewallpolicy-rulecollectiongroups tests
# =============================================================================
# `mock_provider` keeps the suite offline. The positive runs construct the
# bodies; the negative runs abort during variable validation or the
# precondition.
#
# Caveat: mocking bypasses AzAPI's own schema checks, so the positive runs cannot
# confirm ARM accepts a body. The variable validation blocks are the guard.
# =============================================================================

mock_provider "azapi" {}

variables {
  firewall_policy_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/firewallPolicies/afwp-example"
}

run "plans_several_groups" {
  command = plan

  variables {
    groups = {
      platform = {
        name     = "rcg-platform"
        priority = 100
        network_rule_collections = {
          nrc-dns = { priority = 100, rules = [{ name = "dns", protocols = ["UDP"], destination_ports = ["53"], destination_addresses = ["10.0.0.4"], source_addresses = ["*"] }] }
        }
      }
      dnat = {
        priority = 500
        nat_rule_collections = {
          dnat-sftp = { priority = 100, rules = [{ name = "sftp", protocols = ["TCP"], destination_address = "203.0.113.10", destination_ports = ["22"], translated_address = "10.0.2.4", translated_port = "22" }] }
        }
        application_rule_collections = {
          arc-web = { priority = 200, rules = [{ name = "web", protocols = [{ type = "Https", port = 443 }], destination_fqdns = ["example.com"] }] }
        }
      }
    }
  }

  assert {
    condition     = azapi_resource.this["platform"].name == "rcg-platform" && azapi_resource.this["dnat"].name == "dnat"
    error_message = "a group's name must default to its key"
  }
  assert {
    condition     = azapi_resource.this["platform"].parent_id == var.firewall_policy_resource_id && azapi_resource.this["dnat"].body.properties.priority == 500
    error_message = "each group must be a child of the policy, with its own priority"
  }
  assert {
    condition     = length(azapi_resource.this["dnat"].body.properties.ruleCollections) == 2 && azapi_resource.this["dnat"].body.properties.ruleCollections[0].action.type == "Dnat"
    error_message = "a group must send all its collections, NAT first with ARM's Dnat casing"
  }
  assert {
    condition     = azapi_resource.this["dnat"].body.properties.ruleCollections[1].rules[0].targetFqdns[0] == "example.com"
    error_message = "application rules must send destination_fqdns as targetFqdns"
  }
  assert {
    condition     = azapi_resource.this["platform"].locks == tolist([var.firewall_policy_resource_id])
    error_message = "every group must lock the policy"
  }
  assert {
    condition     = azapi_resource.this["platform"].timeouts.update == "60m" && azapi_resource.this["dnat"].timeouts.create == "60m" && azapi_resource.this["dnat"].timeouts.read == "5m"
    error_message = "each group's deadline must allow 30 minutes for every group queued on the policy lock"
  }
  assert {
    condition     = output.groups["dnat"].priority == 500 && output.groups["platform"].name == "rcg-platform"
    error_message = "the outputs must evaluate"
  }
}

run "plans_no_groups_for_an_empty_map" {
  command = plan

  assert {
    condition     = length(azapi_resource.this) == 0 && length(output.groups) == 0
    error_message = "an empty map must create no groups"
  }
}

run "rejects_duplicate_group_names" {
  command = plan

  variables {
    groups = {
      a = { name = "same", priority = 100 }
      b = { name = "same", priority = 200 }
    }
  }

  expect_failures = [var.groups]
}

run "rejects_collection_priority_out_of_range" {
  command = plan

  variables {
    groups = {
      a = {
        priority                 = 100
        network_rule_collections = { nrc = { priority = 70000, rules = [{ name = "r", protocols = ["TCP"], destination_ports = ["1"] }] } }
      }
    }
  }

  expect_failures = [var.groups]
}

run "rejects_duplicate_collection_names_across_kinds" {
  command = plan

  variables {
    groups = {
      a = {
        priority                     = 100
        network_rule_collections     = { shared = { priority = 100, rules = [{ name = "r", protocols = ["TCP"], destination_ports = ["1"] }] } }
        application_rule_collections = { shared = { priority = 200, rules = [{ name = "s", protocols = [{ type = "Https", port = 443 }] }] } }
      }
    }
  }

  expect_failures = [azapi_resource.this["a"]]
}
