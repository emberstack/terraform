resource "fortios_systemdhcp_server" "this" {
  interface       = var.interface
  default_gateway = var.default_gateway
  netmask         = var.netmask
  dns_service     = var.dns_service
  ntp_service     = var.ntp_service
  lease_time      = var.lease_time
  status          = var.status

  dynamic "ip_range" {
    for_each = var.ip_ranges
    content {
      id       = ip_range.value.id
      start_ip = ip_range.value.start_ip
      end_ip   = ip_range.value.end_ip
    }
  }

  # vci_match is `computed` in the provider: leaving it null means "don't manage
  # it", which is why vci_strings alone has no effect — FortiOS defaults
  # vci-match to disable and stores the strings without evaluating them.
  vci_match = var.vci_match

  dynamic "vci_string" {
    for_each = var.vci_strings
    content {
      vci_string = vci_string.value
    }
  }

  dynamic "reserved_address" {
    for_each = var.reserved_addresses
    content {
      id          = reserved_address.value.id
      ip          = reserved_address.value.ip
      mac         = reserved_address.value.mac
      description = reserved_address.value.description
    }
  }

  lifecycle {
    # FortiOS populates dns_server1-3 / ntp_server1-3 from the DHCP server's
    # dns_service and ntp_service mode rather than leaving them empty, so the
    # provider reads back values this module never set. Ignoring them is what
    # keeps plans clean; set dns_service/ntp_service to control the behavior.
    ignore_changes = [dns_server1, dns_server2, dns_server3, ntp_server1, ntp_server2, ntp_server3]
  }
}
