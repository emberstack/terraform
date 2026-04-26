output "name" {
  description = "Stitch name (mkey) as stored on the FortiGate. Use it to reference the stitch from other configuration."
  value       = fortios_system_automationstitch.this.name
}
