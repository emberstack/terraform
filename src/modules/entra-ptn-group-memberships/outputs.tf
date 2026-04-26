output "group_memberships" {
  description = <<-EOT
    Map of created group memberships, keyed by the input map key. Each entry
    exposes the underlying `azuread_group_member` resource attributes:
      - id, group_object_id, member_object_id
  EOT

  value = azuread_group_member.this
}
