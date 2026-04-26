resource "fortios_system_interface" "this" {
  vdom            = var.vdom
  update_if_exist = var.update_if_exist

  name                  = var.name
  alias                 = var.alias
  description           = var.description
  type                  = var.type
  role                  = var.role
  mode                  = var.mode
  ip                    = var.ip != null ? "${var.ip} ${var.netmask}" : null
  allowaccess           = var.allowaccess
  color                 = var.parent_interface != null ? var.color : null
  dns_server_override   = var.dns_server_override
  device_identification = var.device_identification

  # VLAN-specific
  vlanid    = var.vlanid
  interface = var.parent_interface

  # Aggregate-specific
  lacp_mode                 = var.lacp_mode
  fortilink_split_interface = var.fortilink_split_interface

  dynamic "member" {
    for_each = var.members
    content {
      interface_name = member.value
    }
  }

  swc_first_create              = var.swc_first_create
  switch_controller_dynamic     = var.switch_controller_dynamic
  switch_controller_nac         = var.switch_controller_nac
  switch_controller_access_vlan = var.switch_controller_access_vlan
  switch_controller_feature     = var.switch_controller_feature
  security_mode                 = var.security_mode

  auto_auth_extension_device = var.auto_auth_extension_device
  ike_saml_server            = var.ike_saml_server
}

data "fortios_system_interface" "this" {
  name       = var.name
  depends_on = [fortios_system_interface.this]
}

locals {
  _octet_bits = {
    "0"   = 0, "128" = 1, "192" = 2, "224" = 3, "240" = 4,
    "248" = 5, "252" = 6, "254" = 7, "255" = 8
  }
  _actual_ip      = split(" ", data.fortios_system_interface.this.ip)[0]
  _actual_netmask = split(" ", data.fortios_system_interface.this.ip)[1]
  _prefix_length  = sum([for o in split(".", local._actual_netmask) : local._octet_bits[o]])
  _host_bits      = 32 - local._prefix_length
  _network_cidr   = "${cidrhost("${local._actual_ip}/${local._prefix_length}", 0)}/${local._prefix_length}"

  # A /32 (loopbacks, typically) underflows the usual 2^host_bits - 2 to -1 and
  # makes every usable-host output fail with `cidrhost: prefix of 32 does not
  # accommodate a host numbered 1`. Report the single address instead.
  # /31 is left as-is — changing it would alter values callers already consume.
  _single_host  = local._prefix_length == 32
  _host_count   = local._single_host ? 1 : pow(2, local._host_bits) - 2
  _usable_first = local._single_host ? cidrhost(local._network_cidr, 0) : cidrhost(local._network_cidr, 1)
  _usable_last  = local._single_host ? cidrhost(local._network_cidr, 0) : cidrhost(local._network_cidr, local._host_count)
  _range_last   = local._single_host ? cidrhost(local._network_cidr, 0) : cidrhost(local._network_cidr, local._host_count + 1)
}
