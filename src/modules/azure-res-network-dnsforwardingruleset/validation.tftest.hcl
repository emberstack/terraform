# =============================================================================
# azure-res-network-dnsforwardingruleset tests
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
  name                = "dnsfrs-example"
  resource_group_name = "rg-example"
  location            = "westeurope"
  dns_resolver_outbound_endpoint_resource_ids = [
    "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/dnsResolvers/dnspr-example/outboundEndpoints/outbound",
  ]
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans_minimal_ruleset" {
  command = plan

  assert {
    condition     = azapi_resource.this.parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"
    error_message = "the ruleset must be parented on the resource group in the provider's subscription"
  }
  assert {
    condition     = tolist([for e in azapi_resource.this.body.properties.dnsResolverOutboundEndpoints : e.id]) == var.dns_resolver_outbound_endpoint_resource_ids
    error_message = "outbound endpoints must be sent as SubResource objects in input order"
  }
  assert {
    condition     = length(azapi_resource.virtual_network_links) == 0 && length(azapi_resource.role_assignments) == 0 && output.virtual_network_links == {}
    error_message = "no children unless asked for"
  }
  assert {
    condition     = output.resource_group_name == "rg-example"
    error_message = "outputs must evaluate"
  }
}

run "plans_links_and_role_assignments" {
  command = plan

  variables {
    dns_resolver_outbound_endpoint_resource_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/dnsResolvers/dnspr-example/outboundEndpoints/outbound-1",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/dnsResolvers/dnspr-example/outboundEndpoints/outbound-2",
    ]
    virtual_network_links = {
      hub = {
        virtual_network_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-hub"
      }
      spoke = {
        name                        = "Spoke_Link"
        virtual_network_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-spoke/providers/Microsoft.Network/virtualNetworks/vnet-spoke"
        metadata                    = { owner = "platform" }
      }
    }
    role_assignments = {
      reader = {
        role_definition_id_or_name = "Reader"
        principal_id               = "11111111-1111-1111-1111-111111111111"
        principal_type             = "Group"
      }
    }
  }

  assert {
    condition     = azapi_resource.virtual_network_links["hub"].name == "hub" && azapi_resource.virtual_network_links["spoke"].name == "Spoke_Link"
    error_message = "the link's ARM name must default to the map key and honour an explicit name"
  }
  assert {
    condition     = azapi_resource.virtual_network_links["spoke"].body.properties.virtualNetwork.id == var.virtual_network_links["spoke"].virtual_network_resource_id
    error_message = "the link must reference the supplied virtual network"
  }
  assert {
    condition     = azapi_resource.virtual_network_links["spoke"].body.properties.metadata.owner == "platform" && azapi_resource.virtual_network_links["hub"].body.properties.metadata == null
    error_message = "metadata must pass through when set and stay null when not"
  }
  assert {
    condition     = endswith(azapi_resource.role_assignments["reader"].body.properties.roleDefinitionId, "/acdd72a7-3385-48ef-bd42-f606fba81ae7")
    error_message = "a role name must resolve to its definition ID"
  }
  assert {
    condition     = output.virtual_network_links["spoke"].name == "Spoke_Link" && output.virtual_network_links["hub"].virtual_network_resource_id == var.virtual_network_links["hub"].virtual_network_resource_id
    error_message = "outputs must evaluate"
  }
}

# =============================================================================
# NEGATIVE — each validation must fire
# =============================================================================

run "rejects_name_ending_in_hyphen" {
  command = plan
  variables {
    name = "dnsfrs-"
  }
  expect_failures = [var.name]
}

run "rejects_resource_group_id" {
  command = plan
  variables {
    resource_group_name = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"
  }
  expect_failures = [var.resource_group_name]
}

run "rejects_non_outbound_endpoint_id" {
  command = plan
  variables {
    dns_resolver_outbound_endpoint_resource_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/dnsResolvers/dnspr-example/inboundEndpoints/inbound",
    ]
  }
  expect_failures = [var.dns_resolver_outbound_endpoint_resource_ids]
}

run "rejects_no_outbound_endpoints" {
  command = plan
  variables {
    dns_resolver_outbound_endpoint_resource_ids = []
  }
  expect_failures = [var.dns_resolver_outbound_endpoint_resource_ids]
}

run "rejects_three_outbound_endpoints" {
  command = plan
  variables {
    dns_resolver_outbound_endpoint_resource_ids = [
      for i in range(3) : "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/dnsResolvers/dnspr-example/outboundEndpoints/outbound-${i}"
    ]
  }
  expect_failures = [var.dns_resolver_outbound_endpoint_resource_ids]
}

run "rejects_endpoints_from_two_resolvers" {
  command = plan
  variables {
    dns_resolver_outbound_endpoint_resource_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/dnsResolvers/dnspr-a/outboundEndpoints/outbound",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/dnsResolvers/dnspr-b/outboundEndpoints/outbound",
    ]
  }
  expect_failures = [var.dns_resolver_outbound_endpoint_resource_ids]
}

run "rejects_duplicate_outbound_endpoint" {
  command = plan
  variables {
    dns_resolver_outbound_endpoint_resource_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/dnsResolvers/dnspr-example/outboundEndpoints/outbound",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/RG-EXAMPLE/providers/Microsoft.Network/dnsResolvers/dnspr-example/outboundEndpoints/outbound",
    ]
  }
  expect_failures = [var.dns_resolver_outbound_endpoint_resource_ids]
}

run "rejects_link_to_subnet" {
  command = plan
  variables {
    virtual_network_links = {
      hub = {
        virtual_network_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-hub/subnets/snet-a"
      }
    }
  }
  expect_failures = [var.virtual_network_links]
}

run "rejects_link_names_differing_only_in_case" {
  command = plan
  variables {
    virtual_network_links = {
      a = {
        name                        = "Hub"
        virtual_network_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-a"
      }
      b = {
        name                        = "hub"
        virtual_network_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-b"
      }
    }
  }
  expect_failures = [var.virtual_network_links]
}

run "rejects_same_network_linked_twice" {
  command = plan
  variables {
    virtual_network_links = {
      a = {
        virtual_network_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-hub"
      }
      b = {
        virtual_network_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/RG-EXAMPLE/providers/Microsoft.Network/virtualNetworks/vnet-hub"
      }
    }
  }
  expect_failures = [var.virtual_network_links]
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
