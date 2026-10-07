# =============================================================================
# FORTIGATE IPSEC AGGREGATE (fortios_system_ipsecaggregate)
# =============================================================================
# Bundles route-based site-to-site tunnels into one interface for redundancy
# or load-balancing. Each member is a phase1 interface with
# `aggregate_member = "enable"` and `net_device = "disable"`; see
# `fortios-res-fortigate-vpnipsec-phase1interface`. Routes, policies and
# dynamic routing reference the aggregate, never its members.
#
# `name` shares the interface namespace with the members (at most 15
# characters, distinct from every phase1 name) and is ForceNew: a rename
# replaces the aggregate, which FortiOS refuses while routes or policies
# reference it.
#
# `members` is a set on the provider side, so its order carries no meaning
# and does not diff.
# =============================================================================

resource "fortios_system_ipsecaggregate" "this" {
  name      = var.name
  algorithm = var.algorithm

  dynamic "member" {
    for_each = toset(var.members)
    content {
      tunnel_name = member.value
    }
  }
}
