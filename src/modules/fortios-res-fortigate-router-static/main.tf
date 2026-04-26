resource "fortios_router_static" "this" {
  seq_num  = var.seq_num
  dst      = var.dst
  dstaddr  = var.dstaddr
  gateway  = var.gateway
  device   = var.device
  distance = var.distance
  priority = var.priority
  status   = var.status
  comment  = var.comment

  dynamic "sdwan_zone" {
    for_each = var.sdwan_zone != null && var.sdwan_zone != "" ? [var.sdwan_zone] : []
    content {
      name = sdwan_zone.value
    }
  }
}
