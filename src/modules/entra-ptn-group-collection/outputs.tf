output "groups" {
  description = <<-EOT
    Map of created groups, keyed by the input map key.

    Each entry exposes the same outputs as the singular
    `entra-res-group` module:
      - object_id, display_name, mail, mail_nickname, members
  EOT

  value = module.group
}
