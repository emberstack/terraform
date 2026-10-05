# =============================================================================
# FORTIGATE IPSEC PHASE2 INTERFACE (fortios_vpnipsec_phase2interface)
# =============================================================================
# One phase2 selector on a route-based phase1 interface, referenced by
# `phase1name`; see `fortios-res-fortigate-vpnipsec-phase1interface`. A tunnel
# with several selectors gets one instance per selector.
#
# The quick-mode selectors default, on FortiOS, to `0.0.0.0/0` on both sides,
# which is what dial-up and most route-based tunnels want; set `src_*`/`dst_*`
# only to narrow them. Inputs left `null` are not sent and stay unmanaged.
# =============================================================================

resource "fortios_vpnipsec_phase2interface" "this" {
  name       = var.name
  phase1name = var.phase1name
  comments   = var.comments

  proposal       = var.proposal
  pfs            = var.pfs
  dhgrp          = var.dhgrp
  replay         = var.replay
  keepalive      = var.keepalive
  auto_negotiate = var.auto_negotiate
  keylife_type   = var.keylife_type
  keylifeseconds = var.keylifeseconds
  keylifekbs     = var.keylifekbs
  encapsulation  = var.encapsulation
  add_route      = var.add_route

  src_addr_type = var.src_addr_type
  src_subnet    = var.src_subnet
  src_name      = var.src_name
  src_start_ip  = var.src_start_ip
  src_end_ip    = var.src_end_ip
  src_port      = var.src_port
  dst_addr_type = var.dst_addr_type
  dst_subnet    = var.dst_subnet
  dst_name      = var.dst_name
  dst_start_ip  = var.dst_start_ip
  dst_end_ip    = var.dst_end_ip
  dst_port      = var.dst_port
  protocol      = var.protocol

  initiator_ts_narrow = var.initiator_ts_narrow
  single_source       = var.single_source
  route_overlap       = var.route_overlap
}
