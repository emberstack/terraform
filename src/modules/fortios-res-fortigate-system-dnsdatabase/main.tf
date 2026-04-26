resource "fortios_system_dnsdatabase" "this" {
  name          = var.name
  status        = var.status
  type          = var.type
  view          = var.view
  domain        = var.domain
  ttl           = var.ttl
  authoritative = var.authoritative
  primary_name  = var.primary_name
  contact       = var.contact
  forwarder     = var.forwarder
  source_ip     = var.source_ip

  # Provider-level flag — has the fortios SDK sort sub-tables in API
  # responses, helping refresh stability.
  dynamic_sort_subtable = "true"

  # Iterate dns_entries in numeric `id` order so the positional dns_entry
  # blocks emitted here align with box state (FortiOS returns records by id).
  # Without this, alphabetical map-key iteration produces phantom swap diffs.
  # Re-key the map by zero-padded id (lex-sort == numeric order).
  dynamic "dns_entry" {
    for_each = {
      for k, v in var.dns_entries : format("%010d", v.id) => v
    }
    content {
      id             = dns_entry.value.id
      type           = dns_entry.value.type
      hostname       = dns_entry.value.hostname
      ip             = dns_entry.value.ip
      canonical_name = dns_entry.value.canonical_name
      preference     = dns_entry.value.preference
      ttl            = dns_entry.value.ttl
      status         = dns_entry.value.status
    }
  }

  # If a record needs renumbering, edit `id` in the leaf's dns_entries map
  # and apply — the wholesale PUT atomically rewrites the sub-table.
}
