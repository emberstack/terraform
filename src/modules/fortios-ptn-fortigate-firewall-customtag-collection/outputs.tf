output "custom_tags" {
  description = <<-EOT
    Map of the created custom tags, keyed by the `custom_tags` input key.

    Each entry exposes `name`, `abbreviation`, `color`, `comment` and the
    FortiOS-assigned `uuid`.

    Feed `name` into the `custom_tags` list of address, address group and policy
    modules so those objects reference a tag that is known to exist.
  EOT

  value = {
    for k, v in fortios_firewall_customtag.this : k => {
      name         = v.name
      abbreviation = v.abbreviation
      color        = v.color
      comment      = v.comment
      uuid         = v.uuid
    }
  }
}
