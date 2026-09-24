# =============================================================================
# ROUTE TABLE ROUTES
# =============================================================================
# Adds routes to a route table owned elsewhere — `Azure/avm-res-network-routetable`,
# another configuration, or a hand-made table — so several owners can each
# contribute routes to one shared table without any of them redeclaring it.
#
# AVM's `modules/route` submodule manages one route per call. That fits a single
# route with its own lifecycle; this pattern is for a map of routes owned
# together, from one call.
#
# Every write locks the route table, so the map's routes are written one at a
# time. The azurerm provider holds the same lock for `azurerm_route`; without
# it, the map fans out into concurrent PUTs against one parent. The lock is
# process-local — another configuration writing into the same table at the same
# time is what `var.retry` is for.
#
# The table's owner must leave its inline route list alone. ARM writes are full
# replaces, so an owner that sends `properties.routes` removes every route not in
# its own list, this module's included.
# =============================================================================

resource "azapi_resource" "this" {
  for_each = var.routes

  name      = each.value.name
  parent_id = var.route_table_resource_id
  type      = "Microsoft.Network/routeTables/routes@2025-07-01"
  body = {
    properties = {
      addressPrefix = each.value.address_prefix
      # Sent as null for every type but VirtualAppliance rather than omitted, so
      # moving a route off an appliance clears the old address instead of
      # leaving it behind on the full-replace PUT.
      nextHopIpAddress = each.value.next_hop_in_ip_address
      nextHopType      = each.value.next_hop_type
    }
  }

  locks = [var.route_table_resource_id]
  retry = var.retry
}
