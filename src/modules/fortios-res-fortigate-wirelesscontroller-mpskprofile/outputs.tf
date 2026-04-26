output "id" {
  description = "FortiOS resource ID of the MPSK profile (the profile name)."
  value       = fortios_wirelesscontroller_mpskprofile.this.id
}

output "name" {
  description = "Name of the MPSK profile. Use this to reference the profile from a VAP's `mpsk_profile`."
  value       = fortios_wirelesscontroller_mpskprofile.this.name
}
