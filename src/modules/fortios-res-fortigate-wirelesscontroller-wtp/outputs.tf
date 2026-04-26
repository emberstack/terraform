output "id" {
  description = "Resource ID of the managed AP entry as tracked by the fortios provider."
  value       = fortios_wirelesscontroller_wtp.this.id
}

output "wtp_id" {
  description = "Serial number of the managed AP, read back from the resource. Matches the `wtp_id` input."
  value       = fortios_wirelesscontroller_wtp.this.wtp_id
}

output "name" {
  description = "Friendly name assigned to the AP, read back from the resource. Empty when `name` was not set."
  value       = fortios_wirelesscontroller_wtp.this.name
}
