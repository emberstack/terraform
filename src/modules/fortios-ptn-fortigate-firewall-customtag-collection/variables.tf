# abbreviation is what the GUI renders when the tag is shown as a badge —
# FortiOS caps it at three uppercase letters/digits.
variable "custom_tags" {
  description = <<-EOT
    Map of `firewall customtag` entries to create. Custom tags are a single
    global table on the FortiGate; addresses, address groups and policies
    reference them by name, so define the vocabulary once here and consume the
    names elsewhere.

    The map key is the Terraform `for_each` address and the key under which the
    tag appears in the `custom_tags` output — pick stable keys so removing one
    entry doesn't re-address the others.

    Per entry:
      - `name`         — the tag name referenced by other objects.
      - `abbreviation` — short label the GUI renders when the tag is shown as a
                         badge. 1-3 uppercase letters or digits (validated).
      - `color`        — GUI badge colour index, `0`-`32` (validated).
                         Defaults to `0`.
      - `comment`      — free-text comment stored on the tag.
  EOT

  type = map(object({
    name         = string
    abbreviation = optional(string)
    color        = optional(number, 0)
    comment      = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for t in var.custom_tags : t.color >= 0 && t.color <= 32])
    error_message = "color must be between 0 and 32."
  }

  validation {
    condition     = alltrue([for t in var.custom_tags : t.abbreviation == null ? true : can(regex("^[A-Z0-9]{1,3}$", t.abbreviation))])
    error_message = "abbreviation must be 1-3 uppercase letters or digits."
  }
}
