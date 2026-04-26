output "interface_name" {
  description = "Name of the interface enabled as an NTP listener. Echoes the `interface_name` input — the listener is provisioned through the CMDB REST API, so there is no managed resource attribute to read back."
  value       = var.interface_name
}
