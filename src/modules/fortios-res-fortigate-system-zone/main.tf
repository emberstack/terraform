# =============================================================================
# FORTIGATE SYSTEM ZONE (fortios_system_zone)
# =============================================================================
# A named group of interfaces that policies reference in place of its members.
# FortiOS requires that a member is not assigned to another zone and has no
# firewall policies of its own, and refuses to delete a zone that a policy
# still references, so callers order policies after it.
#
# Inputs left `null` are not sent and stay unmanaged. `interfaces` is the
# complete member list.
# =============================================================================

resource "fortios_system_zone" "this" {
  name        = var.name
  intrazone   = var.intrazone
  description = var.description

  dynamic "interface" {
    for_each = toset(var.interfaces)
    content {
      interface_name = interface.value
    }
  }
}
