output "routes" {
  description = <<-EOT
    Map of created static routes, keyed by the same keys as `var.routes`. Each value carries the
    resource `id` plus the route attributes as read back from the FortiGate (`seq_num`, `dst`,
    `dstaddr`, `gateway`, `device`, `distance`, `priority`, `status`, `comment`) — so `seq_num` is
    populated here even when it was left unset on input and assigned by FortiOS. `sdwan_zone` is
    not echoed.
  EOT
  value = {
    for k, v in fortios_router_static.this : k => {
      id       = v.id
      seq_num  = v.seq_num
      dst      = v.dst
      dstaddr  = v.dstaddr
      gateway  = v.gateway
      device   = v.device
      distance = v.distance
      priority = v.priority
      status   = v.status
      comment  = v.comment
    }
  }
}
