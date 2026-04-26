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
