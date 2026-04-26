# =============================================================================
# Custom tag table — the FortiOS 8.0+ tagging vocabulary.
# Tags are a single global table. Addresses, address groups and policies
# reference them by name through their own `custom_tags` input, so define the
# vocabulary once here and consume the names elsewhere.
# =============================================================================

resource "fortios_firewall_customtag" "this" {
  for_each = var.custom_tags

  name         = each.value.name
  abbreviation = each.value.abbreviation
  color        = each.value.color
  comment      = each.value.comment
}
