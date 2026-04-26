output "addresses" {
  description = <<-EOT
    Map of the created `firewall address` objects, keyed by the `addresses`
    input key. Values are read back from the resource, so type-dependent fields
    the module did not send (e.g. `subnet` on an `fqdn` object) come back empty
    rather than as supplied.

    Each entry exposes: `name`, `type`, `subnet`, `start_ip`, `end_ip`, `fqdn`,
    `country`, `interface` (the resource's `associated_interface`), `color`,
    `display_with`, `custom_tags` (flattened to a list of tag names),
    `allow_routing` and `comment`.

    Use `name` from this map when wiring addresses into firewall policies.
  EOT

  value = {
    for k, v in fortios_firewall_address.this : k => {
      name          = v.name
      type          = v.type
      subnet        = v.subnet
      start_ip      = v.start_ip
      end_ip        = v.end_ip
      fqdn          = v.fqdn
      country       = v.country
      interface     = v.associated_interface
      color         = v.color
      display_with  = v.display_with
      custom_tags   = [for t in v.custom_tags : t.name]
      allow_routing = v.allow_routing
      comment       = v.comment
    }
  }
}

output "address_groups" {
  description = <<-EOT
    Map of the created `firewall addrgrp` objects, keyed by the `address_groups`
    input key. Values are read back from the resource.

    Each entry exposes: `name`, `member` (flattened to a list of member names),
    `color`, `display_with`, `custom_tags` (flattened to a list of tag names),
    `allow_routing` and `comment`.

    Use `name` from this map when wiring groups into firewall policies.
  EOT

  value = {
    for k, v in fortios_firewall_addrgrp.this : k => {
      name          = v.name
      member        = [for m in v.member : m.name]
      color         = v.color
      display_with  = v.display_with
      custom_tags   = [for t in v.custom_tags : t.name]
      allow_routing = v.allow_routing
      comment       = v.comment
    }
  }
}
