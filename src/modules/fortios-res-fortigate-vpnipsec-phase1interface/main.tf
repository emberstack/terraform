# =============================================================================
# FORTIGATE IPSEC PHASE1 INTERFACE (fortios_vpnipsec_phase1interface)
# =============================================================================
# One route-based IPsec gateway: site-to-site (`type = "static"`/`"ddns"`) or
# dial-up (`type = "dynamic"`, with mode-cfg handing out client addresses).
# Phase2 selectors are separate objects that reference this one by name; see
# `fortios-res-fortigate-vpnipsec-phase2interface`. FortiOS refuses to delete a
# phase1 that phase2s, routes or policies still reference, so callers order
# those after it.
#
# `psksecret` is never returned by FortiOS, so the provider keeps whatever was
# last configured in state: a key changed on the device out of band is not
# detected.
#
# Inputs left `null` are not sent and stay unmanaged. `certificates` is the
# complete list when set. Empty from the start, the provider neither sends nor
# reads the sub-table; emptying a list that was set sends an empty one, which
# clears it on the device.
# =============================================================================

resource "fortios_vpnipsec_phase1interface" "this" {
  name      = var.name
  interface = var.interface
  type      = var.type
  comments  = var.comments

  ip_version    = var.ip_version
  local_gw      = var.local_gw
  remote_gw     = var.remote_gw
  remotegw_ddns = var.remotegw_ddns

  ike_version       = var.ike_version
  mode              = var.mode
  proposal          = var.proposal
  dhgrp             = var.dhgrp
  keylife           = var.keylife
  negotiate_timeout = var.negotiate_timeout
  nattraversal      = var.nattraversal
  transport         = var.transport
  localid           = var.localid
  localid_type      = var.localid_type

  dpd                  = var.dpd
  dpd_retrycount       = var.dpd_retrycount
  dpd_retryinterval    = var.dpd_retryinterval
  idle_timeout         = var.idle_timeout
  idle_timeoutinterval = var.idle_timeoutinterval

  authmethod   = var.authmethod
  psksecret    = var.psksecret
  peertype     = var.peertype
  peerid       = var.peerid
  peer         = var.peer
  peergrp      = var.peergrp
  eap          = var.eap
  eap_identity = var.eap_identity
  authusrgrp   = var.authusrgrp

  dynamic "certificate" {
    for_each = toset(var.certificates)
    content {
      name = certificate.value
    }
  }

  mode_cfg              = var.mode_cfg
  assign_ip             = var.assign_ip
  assign_ip_from        = var.assign_ip_from
  ipv4_start_ip         = var.ipv4_start_ip
  ipv4_end_ip           = var.ipv4_end_ip
  ipv4_netmask          = var.ipv4_netmask
  ipv4_name             = var.ipv4_name
  ipv4_dns_server1      = var.ipv4_dns_server1
  ipv4_dns_server2      = var.ipv4_dns_server2
  ipv4_dns_server3      = var.ipv4_dns_server3
  ipv4_split_include    = var.ipv4_split_include
  ipv4_split_exclude    = var.ipv4_split_exclude
  save_password         = var.save_password
  client_auto_negotiate = var.client_auto_negotiate
  client_keep_alive     = var.client_keep_alive

  auto_negotiate        = var.auto_negotiate
  add_route             = var.add_route
  net_device            = var.net_device
  exchange_interface_ip = var.exchange_interface_ip
  network_overlay       = var.network_overlay
  network_id            = var.network_id
  wizard_type           = var.wizard_type
}
