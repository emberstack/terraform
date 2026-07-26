output "id" {
  description = "Terraform resource ID of the interface, which is its name."
  value       = fortios_system_interface.this.id
}

output "name" {
  description = "Interface name, read back from the resource. Use this wherever another module needs an interface reference (policies, DHCP servers, zones)."
  value       = fortios_system_interface.this.name
}

output "alias" {
  description = "Interface alias, read back from the resource. Empty when no alias is set."
  value       = fortios_system_interface.this.alias
}

output "role" {
  description = "Effective interface role (`lan`, `wan`, `dmz`, `undefined`), read back from the resource."
  value       = fortios_system_interface.this.role
}

output "mode" {
  description = "Effective addressing mode (`static`, `dhcp`, `pppoe`), read back from the resource."
  value       = fortios_system_interface.this.mode
}

output "vlanid" {
  description = "802.1Q VLAN tag on the interface, read back from the resource. `0` on interfaces that are not VLAN sub-interfaces."
  value       = fortios_system_interface.this.vlanid
}

output "display_name" {
  description = "Human-friendly label for the interface: the alias when one is set, otherwise the interface name. Convenient for naming derived objects and descriptions."
  value       = fortios_system_interface.this.alias != "" ? fortios_system_interface.this.alias : fortios_system_interface.this.name
}

output "color" {
  description = "GUI colour index, read back from the resource. Note the module only *sends* `var.color` when `parent_interface` is set, so for physical and aggregate interfaces this reflects whatever the device already had."
  value       = fortios_system_interface.this.color
}

output "actual_network" {
  description = <<-EOT
    IPv4 addressing derived from the value read back off the device (via the
    `data.fortios_system_interface` lookup), not from `var.ip`/`var.netmask` —
    so it is correct for `dhcp`/`pppoe` interfaces too. Keys:

    - `ipv4_address`       — interface address, e.g. `10.0.10.1`
    - `ipv4_address_cidr`  — interface address with prefix, e.g. `10.0.10.1/24`
    - `ipv4_netmask`       — dotted-quad mask, e.g. `255.255.255.0`
    - `ipv4_network`       — network address with prefix, e.g. `10.0.10.0/24`
    - `ipv4_prefix_length` — prefix length as a number, e.g. `24`
    - `ipv4_prefix`        — prefix length as a string, e.g. `/24`
    - `ipv4_usable_count`  — usable host count (2^host_bits - 2)
    - `ipv4_usable_first`  — first usable host address
    - `ipv4_usable_last`   — last usable host address
    - `ipv4_usable_range`  — `first-last` usable hosts
    - `ipv4_range`         — `network-broadcast`, i.e. the full range including edges

    ⚠️ Two prefixes are special-cased. On a `/32` (loopbacks) the usable-host
    maths would underflow, so the count is reported as `1` and every host value
    collapses to the single address. On a `/31` (point-to-point, RFC 3021)
    there is no network or broadcast address, so the count is `2` and both
    addresses are usable — `ipv4_range` therefore matches `ipv4_usable_range`.
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
