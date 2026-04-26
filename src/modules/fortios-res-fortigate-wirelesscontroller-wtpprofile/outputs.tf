output "id" {
  description = "Resource ID of the AP profile as tracked by the fortios provider."
  value       = fortios_wirelesscontroller_wtpprofile.this.id
}

output "name" {
  description = "Name of the AP profile, read back from the resource. Feed this into a managed AP's `wtp_profile` to bind the profile to an AP."
  value       = fortios_wirelesscontroller_wtpprofile.this.name
}
