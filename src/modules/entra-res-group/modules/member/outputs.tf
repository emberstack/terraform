output "members" {
  description = "Map of azuread_group_member resources, keyed by the input map key."
  value       = azuread_group_member.this
}
