resource "fortios_dnsfilter_domainfilter" "this" {
  fosid   = var.fosid
  name    = var.name
  comment = var.comment

  dynamic "entries" {
    for_each = var.entries
    content {
      id     = entries.value.id
      domain = entries.value.domain
      type   = entries.value.type
      action = entries.value.action
      status = entries.value.status
    }
  }
}
