output "object_id" {
  description = "Object ID of the group."
  value       = azuread_group.this.object_id
}

output "display_name" {
  description = "Display name of the group."
  value       = azuread_group.this.display_name
}

output "mail" {
  description = "Email address of the group, if mail-enabled."
  value       = azuread_group.this.mail
}

output "mail_nickname" {
  description = "Mail alias of the group, if set."
  value       = azuread_group.this.mail_nickname
}

output "members" {
  description = "Map of azuread_group_member resources, keyed by the input map key."
  value       = module.members.members
}
