# =============================================================================
# azure-res-network-firewallpolicy/modules/rule-collection-group tests
# =============================================================================
# `mock_provider` keeps the suite offline. The positive runs construct the body;
# the negative runs abort during variable validation or the precondition.
#
# Caveat: mocking bypasses AzAPI's own schema checks, so the positive runs cannot
# confirm ARM accepts a body. The variable validation blocks are the guard.
# =============================================================================

mock_provider "azapi" {}

variables {
  firewall_policy_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/firewallPolicies/afwp-example"
  name                        = "rcg-example"
  priority                    = 1000
}

run "plans_all_three_collection_kinds" {
  command = plan

  variables {
    nat_rule_collections = {
      dnat-sftp = {
        priority = 100
        rules = [{
          name                = "sftp"
          protocols           = ["TCP"]
          destination_address = "203.0.113.10"
          destination_ports   = ["22"]
          translated_address  = "10.0.2.4"
          translated_port     = "22"
          source_addresses    = ["*"]
        }]
      }
    }
    network_rule_collections = {
      nrc-dns = {
        priority = 200
        rules = [{
          name                  = "dns"
          protocols             = ["UDP", "TCP"]
          destination_addresses = ["10.0.0.4"]
          destination_ports     = ["53"]
          source_addresses      = ["10.0.0.0/8"]
        }]
      }
    }
    application_rule_collections = {
      arc-web = {
        priority = 300
        action   = "Deny"
        rules = [{
          name              = "block-example"
          protocols         = [{ type = "Https", port = 443 }]
          destination_fqdns = ["example.com"]
          source_addresses  = ["*"]
        }]
      }
    }
  }

  assert {
    condition     = azapi_resource.this.parent_id == var.firewall_policy_resource_id && azapi_resource.this.body.properties.priority == 1000
    error_message = "the group must be a child of the policy, with its priority"
  }
  assert {
    condition     = length(azapi_resource.this.body.properties.ruleCollections) == 3
    error_message = "every collection of every kind must be sent"
  }
  assert {
    condition     = azapi_resource.this.body.properties.ruleCollections[0].ruleCollectionType == "FirewallPolicyNatRuleCollection" && azapi_resource.this.body.properties.ruleCollections[0].action.type == "Dnat"
    error_message = "a NAT collection must send ARM's stored action casing, Dnat"
  }
  assert {
    condition     = azapi_resource.this.body.properties.ruleCollections[0].rules[0].destinationAddresses[0] == "203.0.113.10" && azapi_resource.this.body.properties.ruleCollections[0].rules[0].translatedFqdn == null
    error_message = "a NAT rule must wrap its destination address and null the unused translation"
  }
  assert {
    condition     = azapi_resource.this.body.properties.ruleCollections[1].rules[0].ruleType == "NetworkRule" && azapi_resource.this.body.properties.ruleCollections[1].rules[0].ipProtocols[0] == "UDP"
    error_message = "a network rule must send its type and protocols"
  }
  assert {
    condition     = azapi_resource.this.body.properties.ruleCollections[2].action.type == "Deny" && azapi_resource.this.body.properties.ruleCollections[2].rules[0].targetFqdns[0] == "example.com"
    error_message = "an application rule must send destination_fqdns as targetFqdns"
  }
  assert {
    condition     = azapi_resource.this.body.properties.ruleCollections[2].rules[0].protocols[0].protocolType == "Https" && azapi_resource.this.body.properties.ruleCollections[2].rules[0].protocols[0].port == 443
    error_message = "application protocols must be sent as protocolType/port"
  }
  assert {
    condition     = azapi_resource.this.locks == tolist([var.firewall_policy_resource_id])
    error_message = "the group must lock the policy"
  }
  assert {
    condition     = output.name == "rcg-example" && output.priority == 1000
    error_message = "the outputs must evaluate"
  }
}

run "rejects_duplicate_collection_names_across_kinds" {
  command = plan

  variables {
    network_rule_collections = {
      shared = { priority = 200, rules = [{ name = "a", protocols = ["TCP"], destination_ports = ["1"] }] }
    }
    application_rule_collections = {
      shared = { priority = 300, rules = [{ name = "b", protocols = [{ type = "Https", port = 443 }] }] }
    }
  }

  expect_failures = [azapi_resource.this]
}

run "rejects_priority_out_of_range" {
  command = plan

  variables {
    priority = 99
  }

  expect_failures = [var.priority]
}

run "rejects_nat_rule_with_both_translations" {
  command = plan

  variables {
    nat_rule_collections = {
      dnat = {
        priority = 100
        rules = [{
          name                = "both"
          protocols           = ["TCP"]
          destination_address = "203.0.113.10"
          destination_ports   = ["22"]
          translated_address  = "10.0.2.4"
          translated_fqdn     = "sftp.example.com"
          translated_port     = "22"
        }]
      }
    }
  }

  expect_failures = [var.nat_rule_collections]
}

run "rejects_duplicate_rule_names" {
  command = plan

  variables {
    network_rule_collections = {
      nrc = {
        priority = 200
        rules = [
          { name = "dup", protocols = ["TCP"], destination_ports = ["1"] },
          { name = "dup", protocols = ["UDP"], destination_ports = ["2"] },
        ]
      }
    }
  }

  expect_failures = [var.network_rule_collections]
}

run "rejects_unknown_application_protocol" {
  command = plan

  variables {
    application_rule_collections = {
      arc = { priority = 300, rules = [{ name = "x", protocols = [{ type = "Mssql", port = 1433 }] }] }
    }
  }

  expect_failures = [var.application_rule_collections]
}
