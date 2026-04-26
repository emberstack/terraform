# display_with defaults to icon-and-color so `color` actually renders; FortiOS
# 8.0+ can show custom_tags badges instead.
variable "addresses" {
  description = <<-EOT
    Map of `firewall address` objects to create. The map key is the Terraform
    `for_each` address and the key under which the object appears in the
    `addresses` output — pick stable keys so removing one entry doesn't
    re-address the others.

    Per entry:
      - `name`          — the address object name as it appears on the FortiGate.
      - `type`          — address kind. One of `ipmask`, `iprange`, `fqdn` or
                          `geography`. Defaults to `ipmask`.
      - `subnet`        — only sent when `type` is `ipmask`, ignored otherwise.
      - `start_ip` /
        `end_ip`        — only sent when `type` is `iprange`, ignored otherwise.
      - `fqdn`          — only sent when `type` is `fqdn`, ignored otherwise.
      - `country`       — two-letter country code; only sent when `type` is
                          `geography`, ignored otherwise.
      - `interface`     — maps to `associated_interface`; scopes the object to a
                          single interface. Sent regardless of `type`.
      - `color`         — GUI icon colour index (`0` = default palette entry).
      - `display_with`  — what the GUI shows next to the object. Defaults to
                          `icon-and-color` so `color` actually renders; FortiOS
                          8.0+ also accepts tag-badge modes.
      - `custom_tags`   — list of `firewall customtag` names to attach. Each
                          entry emits one `custom_tags` block; an empty list
                          emits none. The tags must already exist (see
                          `fortios-ptn-fortigate-firewall-customtag-collection`).
      - `allow_routing` — whether the object may be used in static routes.
                          One of `enable` or `disable`. Defaults to `disable`.
      - `comment`       — free-text comment stored on the object.
  EOT

  type = map(object({
    name          = string
    type          = optional(string, "ipmask")
    subnet        = optional(string)
    start_ip      = optional(string)
    end_ip        = optional(string)
    fqdn          = optional(string)
    country       = optional(string)
    interface     = optional(string)
    color         = optional(number, 0)
    display_with  = optional(string, "icon-and-color")
    custom_tags   = optional(list(string), [])
    allow_routing = optional(string, "disable")
    comment       = optional(string)
  }))
  default = {}
}

# display_with is deliberately NOT defaulted here: FortiOS honours it on
# addresses but reverts groups to all-tags, so a default would diff forever.
variable "address_groups" {
  description = <<-EOT
    Map of `firewall addrgrp` objects to create. The map key is the Terraform
    `for_each` address and the key under which the group appears in the
    `address_groups` output.

    Groups are created after all `addresses` entries (explicit `depends_on`), so
    a group may reference members defined in the same module call.

    Per entry:
      - `name`          — the address group name as it appears on the FortiGate.
      - `member`        — list of member address / address group names. Each
                          entry emits one `member` block. Names are not resolved
                          by this module — they must already exist on the device
                          or be created by the `addresses` input.
      - `color`         — GUI icon colour index (`0` = default palette entry).
      - `display_with`  — what the GUI shows next to the group. Deliberately has
                          no default: FortiOS honours it on addresses but reverts
                          groups to all-tags, so a default would produce a
                          perpetual diff. Leave unset unless you have a reason.
      - `custom_tags`   — list of `firewall customtag` names to attach. Each
                          entry emits one `custom_tags` block; an empty list
                          emits none.
      - `allow_routing` — whether the group may be used in static routes.
                          One of `enable` or `disable`. Defaults to `disable`.
      - `comment`       — free-text comment stored on the group.
  EOT

  type = map(object({
    name          = string
    member        = list(string)
    color         = optional(number, 0)
    display_with  = optional(string)
    custom_tags   = optional(list(string), [])
    allow_routing = optional(string, "disable")
    comment       = optional(string)
  }))
  default = {}
}
