resource "fortios_router_static" "this" {
  for_each = var.routes

  seq_num  = each.value.seq_num
  dst      = each.value.dst
  dstaddr  = each.value.dstaddr
  gateway  = each.value.gateway
  device   = each.value.device
  distance = each.value.distance
  priority = each.value.priority
  status   = each.value.status
  comment  = each.value.comment

  dynamic "sdwan_zone" {
    for_each = each.value.sdwan_zone != null ? [each.value.sdwan_zone] : []
    content {
      name = sdwan_zone.value
    }
  }
}
