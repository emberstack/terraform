# =============================================================================
# FORTIGATE SYSTEM ACME (fortios_system_acme)
# =============================================================================
# `system acme` is a singleton: create and update both write it, and destroy
# clears the listening interfaces and resets the other managed attributes.
#
# `accounts` is deliberately not exposed. FortiOS registers the ACME account
# itself the first time a certificate is enrolled, and the entry carries the
# account's private key. Left unconfigured, the provider neither reads nor
# sends the sub-table, so the account survives every apply and destroy and a
# renewal keeps using it. Never set `get_all_tables` here: it would pull the
# key into state.
# =============================================================================

resource "fortios_system_acme" "this" {
  source_ip     = var.source_ip
  source_ip6    = var.source_ip6
  use_ha_direct = var.use_ha_direct

  dynamic "interface" {
    for_each = toset(var.interfaces)
    content {
      interface_name = interface.value
    }
  }
}
