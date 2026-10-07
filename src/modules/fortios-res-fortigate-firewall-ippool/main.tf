# =============================================================================
# FORTIGATE FIREWALL IP POOL (fortios_firewall_ippool)
# =============================================================================
# One source-NAT address pool. A policy uses it through `ippool = "enable"`
# and `poolname`; see `fortios-res-fortigate-firewall-policy`. FortiOS refuses
# to delete a pool that a policy still references, so callers order policies
# after it.
#
# Inputs left `null` are not sent and stay unmanaged.
# =============================================================================

resource "fortios_firewall_ippool" "this" {
  name      = var.name
  type      = var.type
  startip   = var.startip
  endip     = var.endip
  arp_reply = var.arp_reply
  comments  = var.comments
}
