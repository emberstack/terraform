output "object_id" {
  description = "Object ID of the administrative unit."
  value       = azuread_administrative_unit.this.object_id
}

output "display_name" {
  description = "Display name of the administrative unit."
  value       = azuread_administrative_unit.this.display_name
}

output "members" {
  description = "Map of administrative_unit_member resources, keyed by the input map key."
  value       = module.members.members
}

output "role_assignments" {
  description = "Map of azuread_directory_role_assignment resources, keyed by the input map key."
  value       = azuread_directory_role_assignment.this
}
