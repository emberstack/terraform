# =============================================================================
# FORTIGATE USER GROUP (fortios_user_group)
# =============================================================================
# A user group for firewall authentication: local users or remote servers as
# members, and optional matches that narrow a remote server to the users of
# one of its groups, e.g. a SAML server and an Entra group object ID.
#
# Guest, RSSO and SCIM attributes are not exposed.
#
# `match` ids are assigned from list position (1, 2, ...), so they stay stable
# as long as the order of `matches` does.
# =============================================================================

resource "fortios_user_group" "this" {
  name        = var.name
  group_type  = var.group_type
  authtimeout = var.authtimeout

  dynamic "member" {
    for_each = toset(var.members)
    content {
      name = member.value
    }
  }

  dynamic "match" {
    for_each = { for index, match in var.matches : index => match }
    content {
      id          = match.key + 1
      server_name = match.value.server_name
      group_name  = match.value.group_name
    }
  }
}
