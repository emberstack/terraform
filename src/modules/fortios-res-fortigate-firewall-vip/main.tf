# =============================================================================
# FORTIGATE FIREWALL VIP (fortios_firewall_vip)
# =============================================================================
# One virtual IP: destination NAT from `extip` to the `mappedip` ranges,
# optionally per port. Policies reference it by name as a destination address.
# FortiOS refuses to delete a VIP that a policy still references.
#
# Inputs left `null` are not sent and stay unmanaged. `mappedip` is the
# complete list.
# =============================================================================

resource "fortios_firewall_vip" "this" {
  name        = var.name
  type        = var.type
  extip       = var.extip
  extintf     = var.extintf
  portforward = var.portforward
  protocol    = var.protocol
  extport     = var.extport
  mappedport  = var.mappedport
  arp_reply   = var.arp_reply
  color       = var.color
  comment     = var.comment

  dynamic "mappedip" {
    for_each = var.mappedip
    content {
      range = mappedip.value
    }
  }
}
