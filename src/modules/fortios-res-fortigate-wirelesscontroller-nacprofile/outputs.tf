output "id" {
  description = "FortiOS resource ID of the wireless NAC profile (the profile name)."
  value       = fortios_wirelesscontroller_nacprofile.this.id
}

output "name" {
  description = "Name of the wireless NAC profile. Use this to reference the profile from a VAP's `nac_profile`."
  value       = fortios_wirelesscontroller_nacprofile.this.name
}
