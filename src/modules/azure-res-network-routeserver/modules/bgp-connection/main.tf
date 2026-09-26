# =============================================================================
# ROUTE SERVER BGP CONNECTION (Microsoft.Network/virtualHubs/bgpConnections)
# =============================================================================
# One BGP peering between a route server and an NVA. Kept apart from the parent
# because the two usually have different owners: the route server belongs to
# the hub, the peering to whatever configuration deploys the NVA and knows its
# address and ASN.
#
# Creating the connection only lets the route server accept the session. The
# NVA still has to peer with both of the route server's `virtual_router_ips`,
# as remote AS `virtual_router_asn`.
# =============================================================================

resource "azapi_resource" "this" {
  name      = var.name
  parent_id = var.route_server_resource_id
  type      = "Microsoft.Network/virtualHubs/bgpConnections@2025-07-01"
  body = {
    properties = {
      peerAsn = var.peer_asn
      peerIp  = var.peer_ip
    }
  }
  response_export_values = {
    connection_state = "properties.connectionState"
  }
}
