# =============================================================================
# VIRTUAL NETWORK DNS SERVERS
# =============================================================================
# Sets the DNS servers on an existing virtual network without redeclaring the
# vnet itself. No new Azure resource is created — only the existing vnet's
# `properties.dhcpOptions.dnsServers` is written.
#
# This pattern exists to break the hub-spoke + NVA cycle: when DNS comes from a
# firewall *inside* the same vnet, the vnet cannot reference the firewall inline.
# Splitting DNS-server assignment into a downstream module breaks the cycle.
#
# The vnet is owned by another module (typically AVM). That owner must not clear
# `dhcpOptions` on its own writes — see the README for the `ignore_changes`
# contract callers are expected to honour.
#
# ARM exposes no property-level PATCH for virtual networks (only tags), so this
# is a read-merge-write of the whole vnet. Everything not named in `body` is
# echoed back untouched, including subnets and peerings.
# =============================================================================

resource "azapi_update_resource" "this" {
  resource_id = var.virtual_network_resource_id
  type        = "Microsoft.Network/virtualNetworks@2025-09-01"
  body = {
    properties = {
      dhcpOptions = {
        dnsServers = var.dns_servers
      }
    }
  }
}
