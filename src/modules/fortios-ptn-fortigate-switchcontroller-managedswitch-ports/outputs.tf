output "managed_port_count" {
  description = "Number of ports this module manages on the switch."
  value       = length(var.ports)
}
