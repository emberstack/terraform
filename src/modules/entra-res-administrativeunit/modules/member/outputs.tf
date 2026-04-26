output "members" {
  description = "Map of administrative_unit_member resources, keyed by the input map key."
  value       = azuread_administrative_unit_member.this
}
