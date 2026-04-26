output "id" {
  description = "Terraform resource ID of the SSID policy, which for this provider is the policy name (the FortiOS mkey)."
  value       = fortios_wirelesscontroller_ssidpolicy.this.id
}

output "name" {
  description = "Name of the SSID policy as stored on the FortiGate. Use this when referencing the policy from a VAP."
  value       = fortios_wirelesscontroller_ssidpolicy.this.name
}
