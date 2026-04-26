resource "fortios_firewall_policy" "this" {
  policyid         = var.policyid
  name             = var.name
  action           = var.action
  schedule         = var.schedule
  nat              = var.nat
  status           = var.status
  logtraffic       = var.logtraffic
  logtraffic_start = var.logtraffic_start
  comments         = var.comments
  session_ttl      = var.session_ttl

  dynamic "srcintf" {
    for_each = var.srcintf
    content {
      name = srcintf.value
    }
  }

  dynamic "dstintf" {
    for_each = var.dstintf
    content {
      name = dstintf.value
    }
  }

  dynamic "srcaddr" {
    for_each = var.srcaddr
    content {
      name = srcaddr.value
    }
  }

  dynamic "dstaddr" {
    for_each = var.dstaddr
    content {
      name = dstaddr.value
    }
  }

  dynamic "service" {
    for_each = var.service
    content {
      name = service.value
    }
  }

  dynamic "groups" {
    for_each = var.groups
    content {
      name = groups.value
    }
  }
}
