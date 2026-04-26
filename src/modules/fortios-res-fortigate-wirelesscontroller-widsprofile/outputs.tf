output "id" {
  description = "Resource ID of the WIDS profile as tracked by the fortios provider."
  value       = fortios_wirelesscontroller_widsprofile.this.id
}

output "name" {
  description = "Name of the WIDS profile, read back from the resource. Feed this into a wtp-profile radio's `wids_profile` to bind the profile to a radio."
  value       = fortios_wirelesscontroller_widsprofile.this.name
}
