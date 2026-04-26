output "id" {
  description = "Terraform resource ID of the VAP, which for this provider is the VAP name (the FortiOS mkey)."
  value       = fortios_wirelesscontroller_vap.this.id
}

output "name" {
  description = "Name of the VAP as stored on the FortiGate. This is also the interface name to reference from firewall policies, DHCP servers and wtp-profile VAP lists."
  value       = fortios_wirelesscontroller_vap.this.name
}

output "ssid" {
  description = "SSID broadcast by the VAP, read back from the resource."
  value       = fortios_wirelesscontroller_vap.this.ssid
}
