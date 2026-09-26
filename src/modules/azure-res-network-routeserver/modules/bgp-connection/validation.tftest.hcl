# =============================================================================
# azure-res-network-routeserver/modules/bgp-connection tests
# =============================================================================
# `mock_provider` keeps the suite offline. The positive run constructs the
# resource and evaluates the outputs; the negative runs abort during variable
# validation.
#
# Caveat: mocking bypasses AzAPI's own schema checks, so the positive run cannot
# confirm ARM accepts a body. The variable validation blocks are the guard.
# =============================================================================

mock_provider "azapi" {}

variables {
  route_server_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualHubs/rs-example"
  name                     = "nva-example"
  peer_asn                 = 65001
  peer_ip                  = "10.0.1.4"
}

run "plans_bgp_connection" {
  command = plan

  assert {
    condition     = azapi_resource.this.parent_id == var.route_server_resource_id && azapi_resource.this.name == "nva-example"
    error_message = "the connection must be a named child of the route server"
  }
  assert {
    condition     = azapi_resource.this.body.properties.peerAsn == 65001 && azapi_resource.this.body.properties.peerIp == "10.0.1.4"
    error_message = "the peer ASN and IP must be sent as configured"
  }
  assert {
    condition     = output.peer_asn == 65001 && output.peer_ip == "10.0.1.4"
    error_message = "the outputs must evaluate — this is the run that catches bad attribute references"
  }
}

run "rejects_route_server_asn" {
  command = plan

  variables {
    peer_asn = 65515
  }

  expect_failures = [var.peer_asn]
}

run "rejects_iana_reserved_asn" {
  command = plan

  variables {
    peer_asn = 64500
  }

  expect_failures = [var.peer_asn]
}

run "rejects_ipv6_peer" {
  command = plan

  variables {
    peer_ip = "fd00::4"
  }

  expect_failures = [var.peer_ip]
}

run "rejects_parent_that_is_not_a_virtual_hub" {
  command = plan

  variables {
    route_server_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworkGateways/vgw-example"
  }

  expect_failures = [var.route_server_resource_id]
}
