# =============================================================================
# VIRTUAL NETWORK DNS SERVERS (pattern module)
# =============================================================================
# Sets the DNS servers on an existing virtual network without redeclaring the
# vnet itself. The underlying `azurerm_virtual_network_dns_servers` resource
# does not create a new Azure resource — it just PATCHes the existing vnet's
# `dhcpOptions.dnsServers`.
#
# This pattern exists to break the hub-spoke + NVA cycle: when DNS comes from
# a firewall *inside* the same vnet, the vnet cannot reference the firewall
# inline. Splitting DNS-server assignment into a downstream module breaks the
# cycle.
# =============================================================================

resource "azurerm_virtual_network_dns_servers" "this" {
  virtual_network_id = var.virtual_network_resource_id
  dns_servers        = var.dns_servers
}
