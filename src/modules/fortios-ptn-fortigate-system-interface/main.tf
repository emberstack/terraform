# =============================================================================
# Standard interface — one VLAN/physical interface with optional satellites.
# Resources are inlined (not composed via module blocks) so the pattern stays
# self-contained when copied to terragrunt-cache.
# =============================================================================

# -----------------------------------------------------------------------------
# Interface
# -----------------------------------------------------------------------------

resource "fortios_system_interface" "this" {
  vdom            = "root"
  update_if_exist = true

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

  # VLAN
  vlanid    = var.vlanid
  interface = var.parent_interface

  # Aggregate
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

  # Third copy of this maths in the repo (see fortios-res-fortigate-system-interface
  # and fortios-utl-network-cidr) — kept in sync. A /32 underflows 2^host_bits - 2
  # to -1 and makes every usable-host value fail with `cidrhost: prefix of 32 does
  # not accommodate a host numbered 1`; report the single address instead. A /31 is
  # a point-to-point link with no network or broadcast address (RFC 3021), so both
  # addresses are usable. It needs its own `_range_offset` branch: host_count + 1
  # would be 3, and a /31 only has hosts 0 and 1.
  _single_host    = local._prefix_length == 32
  _point_to_point = local._prefix_length == 31
  _host_count     = local._single_host ? 1 : local._point_to_point ? 2 : pow(2, local._host_bits) - 2

  _first_offset = local._single_host || local._point_to_point ? 0 : 1
  _last_offset  = local._single_host ? 0 : local._point_to_point ? 1 : local._host_count
  _range_offset = local._single_host ? 0 : local._point_to_point ? 1 : local._host_count + 1

  _usable_first = cidrhost(local._network_cidr, local._first_offset)
  _usable_last  = cidrhost(local._network_cidr, local._last_offset)
  _range_last   = cidrhost(local._network_cidr, local._range_offset)
}

# -----------------------------------------------------------------------------
# Addresses + groups
# -----------------------------------------------------------------------------

resource "fortios_firewall_address" "this" {
  for_each = var.addresses

  name          = each.value.name
  type          = each.value.type
  color         = each.value.color
  display_with  = each.value.display_with
  allow_routing = each.value.allow_routing
  comment       = each.value.comment

  subnet               = each.value.type == "ipmask" ? each.value.subnet : null
  start_ip             = each.value.type == "iprange" ? each.value.start_ip : null
  end_ip               = each.value.type == "iprange" ? each.value.end_ip : null
  fqdn                 = each.value.type == "fqdn" ? each.value.fqdn : null
  country              = each.value.type == "geography" ? each.value.country : null
  associated_interface = each.value.interface

  dynamic "custom_tags" {
    for_each = each.value.custom_tags
    content {
      name = custom_tags.value
    }
  }
}

resource "fortios_firewall_addrgrp" "this" {
  for_each = var.address_groups

  name          = each.value.name
  color         = each.value.color
  display_with  = each.value.display_with
  allow_routing = each.value.allow_routing
  comment       = each.value.comment

  dynamic "member" {
    for_each = each.value.member
    content {
      name = member.value
    }
  }

  dynamic "custom_tags" {
    for_each = each.value.custom_tags
    content {
      name = custom_tags.value
    }
  }

  depends_on = [fortios_firewall_address.this]
}

# -----------------------------------------------------------------------------
# DHCP server
# -----------------------------------------------------------------------------

resource "fortios_systemdhcp_server" "this" {
  count = var.dhcp_server == null ? 0 : 1

  interface       = fortios_system_interface.this.name
  default_gateway = var.dhcp_server.default_gateway
  netmask         = var.dhcp_server.netmask
  dns_service     = var.dhcp_server.dns_service
  ntp_service     = var.dhcp_server.ntp_service
  lease_time      = var.dhcp_server.lease_time
  status          = var.dhcp_server.status

  dynamic "ip_range" {
    for_each = var.dhcp_server.ip_ranges
    content {
      id       = ip_range.value.id
      start_ip = ip_range.value.start_ip
      end_ip   = ip_range.value.end_ip
    }
  }

  dynamic "vci_string" {
    for_each = var.dhcp_server.vci_strings
    content {
      vci_string = vci_string.value
    }
  }

  dynamic "reserved_address" {
    for_each = var.dhcp_server.reserved_addresses
    content {
      id          = reserved_address.value.id
      ip          = reserved_address.value.ip
      mac         = reserved_address.value.mac
      description = reserved_address.value.description
    }
  }

  lifecycle {
    ignore_changes = [dns_server1, dns_server2, dns_server3, ntp_server1, ntp_server2, ntp_server3]
  }
}

# -----------------------------------------------------------------------------
# DNS server (optional singleton)
# -----------------------------------------------------------------------------

resource "fortios_system_dnsserver" "this" {
  count = var.dns_server == null ? 0 : 1

  name              = fortios_system_interface.this.name
  mode              = var.dns_server.mode
  dnsfilter_profile = var.dns_server.dnsfilter_profile
}

# -----------------------------------------------------------------------------
# NTP listener (optional — system/ntp/interface is a sub-table not exposed as
# a native fortios resource, so we provision via direct REST API).
# -----------------------------------------------------------------------------

data "fortios_system_ntp" "current" {
  count = var.ntp_listener ? 1 : 0
}

locals {
  _ntp_current_interfaces = var.ntp_listener ? [for i in try(data.fortios_system_ntp.current[0].interface, []) : i.interface_name] : []
  _ntp_already_exists     = contains(local._ntp_current_interfaces, var.name)
}

resource "terraform_data" "ntp_listener" {
  count = var.ntp_listener ? 1 : 0

  input = {
    interface_name = fortios_system_interface.this.name
    owned          = !local._ntp_already_exists
  }

  lifecycle {
    ignore_changes = [input]
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-NoProfile", "-Command"]
    command     = <<-EOT
      if ("${self.input.owned}" -eq "true") {
        Invoke-RestMethod `
          -Uri "https://$env:FORTIOS_ACCESS_HOSTNAME/api/v2/cmdb/system/ntp/interface" `
          -Method POST `
          -Headers @{ Authorization = "Bearer $env:FORTIOS_ACCESS_TOKEN" } `
          -Body '${jsonencode({ "interface-name" = var.name })}' `
          -ContentType "application/json" `
          -SkipCertificateCheck | Out-Null
        Write-Host "Added NTP listener: ${var.name}"
      } else {
        Write-Host "NTP listener already exists: ${var.name}"
      }
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["pwsh", "-NoProfile", "-Command"]
    command     = <<-EOT
      if ("${self.input.owned}" -eq "true") {
        try {
          Invoke-RestMethod `
            -Uri "https://$env:FORTIOS_ACCESS_HOSTNAME/api/v2/cmdb/system/ntp/interface/${self.input.interface_name}" `
            -Method DELETE `
            -Headers @{ Authorization = "Bearer $env:FORTIOS_ACCESS_TOKEN" } `
            -SkipCertificateCheck | Out-Null
          Write-Host "Removed NTP listener: ${self.input.interface_name}"
        } catch {
          if ($_.Exception.Response.StatusCode.value__ -eq 404) {
            Write-Host "NTP listener already gone: ${self.input.interface_name}"
          } else { throw }
        }
      } else {
        Write-Host "NTP listener was pre-existing — skipping cleanup: ${self.input.interface_name}"
      }
    EOT
  }
}
