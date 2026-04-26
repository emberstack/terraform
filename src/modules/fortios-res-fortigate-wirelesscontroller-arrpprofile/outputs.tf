output "id" {
  description = "FortiOS resource ID of the ARRP profile (the profile name)."
  value       = fortios_wirelesscontroller_arrpprofile.this.id
}

output "name" {
  description = "Name of the ARRP profile. Use this to reference the profile from a WTP profile radio's `arrp_profile`."
  value       = fortios_wirelesscontroller_arrpprofile.this.name
}
