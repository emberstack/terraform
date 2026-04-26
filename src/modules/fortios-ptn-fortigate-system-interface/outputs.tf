# Pass-through outputs.
#
# Interface fields are flat (interface is the primary subject of this pattern).
# Satellite outputs (addresses, address_groups, dhcp_server, dns_server) are
# grouped — null/empty when the satellite wasn't configured. Downstream check:
#   if dependency.<vlan>.outputs.dhcp_server != null { ... }

# Interface
output "id" {
  description = "Terraform resource ID of the interface, which is the FortiOS interface name."
  value       = fortios_system_interface.this.id
}
output "name" {
  description = "Interface name as configured on the FortiGate. Use this to reference the interface from firewall policies, routes, or other modules."
  value       = fortios_system_interface.this.name
}
output "alias" {
  description = "Alias set on the interface. Empty string when none was supplied."
  value       = fortios_system_interface.this.alias
}
output "role" {
  description = "Interface role in effect (`lan`, `wan`, `dmz` or `undefined`)."
  value       = fortios_system_interface.this.role
}
output "mode" {
  description = "IPv4 addressing mode in effect (`static`, `dhcp` or `pppoe`)."
  value       = fortios_system_interface.this.mode
}
output "vlanid" {
  description = "802.1Q VLAN tag on the interface. Null/zero on non-VLAN interfaces."
  value       = fortios_system_interface.this.vlanid
}
output "color" {
  description = "GUI colour index on the interface. Reflects whatever FortiOS settled on, which is not necessarily the `color` input — the module only sends it for VLAN sub-interfaces."
  value       = fortios_system_interface.this.color
}
output "display_name" {
  description = "The alias when one is set, otherwise the interface name. Convenience value for labelling the interface in downstream naming."
  value       = fortios_system_interface.this.alias != "" ? fortios_system_interface.this.alias : fortios_system_interface.this.name
}
output "actual_network" {
  description = <<-EOT
    Addressing facts derived from the address FortiOS actually reports back on
    the interface (read via a `data` source after apply), not from the `ip`
    input — so it is correct for DHCP/PPPoE interfaces too. Fields:

    - `ipv4_address` — interface address, e.g. `10.0.10.1`
    - `ipv4_address_cidr` — interface address with prefix, e.g. `10.0.10.1/24`
    - `ipv4_netmask` — dotted-decimal mask
    - `ipv4_network` — network address with prefix, e.g. `10.0.10.0/24`
    - `ipv4_prefix_length` — prefix length as a number
    - `ipv4_prefix` — prefix length as a string, e.g. `/24`
    - `ipv4_usable_count` — usable host count (network and broadcast excluded)
    - `ipv4_usable_first` / `ipv4_usable_last` — first and last usable host
    - `ipv4_usable_range` — first-last usable hosts, hyphen separated
    - `ipv4_range` — network-broadcast, hyphen separated

    Feed these into DHCP pools, firewall address objects, and route targets
    instead of recomputing CIDR math at the call site.
  EOT
  value = {
    ipv4_address       = local._actual_ip
    ipv4_address_cidr  = "${local._actual_ip}/${local._prefix_length}"
    ipv4_netmask       = local._actual_netmask
    ipv4_network       = local._network_cidr
    ipv4_prefix_length = local._prefix_length
    ipv4_prefix        = "/${local._prefix_length}"
    ipv4_usable_count  = local._host_count
    ipv4_usable_first  = local._usable_first
    ipv4_usable_last   = local._usable_last
    ipv4_usable_range  = "${local._usable_first}-${local._usable_last}"
    ipv4_range         = "${cidrhost(local._network_cidr, 0)}-${local._range_last}"
  }
}

# Addresses — flat maps; empty if none declared.
output "addresses" {
  description = "Firewall address objects created by this module, keyed by the same key used in the `addresses` input. Each value mirrors the resource's fields (`name`, `type`, `subnet`, `start_ip`, `end_ip`, `fqdn`, `country`, `interface`, `color`, `display_with`, `custom_tags`, `allow_routing`, `comment`). Empty map when none were declared."
  value = {
    for k, v in fortios_firewall_address.this : k => {
      name          = v.name
      type          = v.type
      subnet        = v.subnet
      start_ip      = v.start_ip
      end_ip        = v.end_ip
      fqdn          = v.fqdn
      country       = v.country
      interface     = v.associated_interface
      color         = v.color
      display_with  = v.display_with
      custom_tags   = [for t in v.custom_tags : t.name]
      allow_routing = v.allow_routing
      comment       = v.comment
    }
  }
}

output "address_groups" {
  description = "Firewall address groups created by this module, keyed by the same key used in the `address_groups` input. `member` is flattened to a list of member names. Empty map when none were declared."
  value = {
    for k, v in fortios_firewall_addrgrp.this : k => {
      name          = v.name
      member        = [for m in v.member : m.name]
      color         = v.color
      display_with  = v.display_with
      custom_tags   = [for t in v.custom_tags : t.name]
      allow_routing = v.allow_routing
      comment       = v.comment
    }
  }
}

# Satellite services — null when not configured.
output "dhcp_server" {
  description = "The DHCP server created on this interface as `{ id, interface }`, where `id` is the FortiOS numeric server ID. Null when `dhcp_server` was not supplied."
  value = try({
    id        = fortios_systemdhcp_server.this[0].fosid
    interface = fortios_systemdhcp_server.this[0].interface
  }, null)
}

output "dns_server" {
  description = "The DNS server created on this interface as `{ id, name, mode, dnsfilter_profile }`. Null when `dns_server` was not supplied."
  value = try({
    id                = fortios_system_dnsserver.this[0].id
    name              = fortios_system_dnsserver.this[0].name
    mode              = fortios_system_dnsserver.this[0].mode
    dnsfilter_profile = fortios_system_dnsserver.this[0].dnsfilter_profile
  }, null)
}

output "ntp_listener" {
  description = "Echoes the `ntp_listener` input rather than reading back from the device — the listener is provisioned out-of-band via the REST API, so there is no resource attribute to report."
  value       = var.ntp_listener
}
