resource "fortios_firewallservice_custom" "this" {
  name           = var.name
  category       = var.category
  protocol       = var.protocol
  tcp_portrange  = length(var.tcp_portrange) > 0 ? join(" ", var.tcp_portrange) : null
  udp_portrange  = length(var.udp_portrange) > 0 ? join(" ", var.udp_portrange) : null
  sctp_portrange = length(var.sctp_portrange) > 0 ? join(" ", var.sctp_portrange) : null
  color          = var.color
  comment        = var.comment
  session_ttl    = var.session_ttl
}
