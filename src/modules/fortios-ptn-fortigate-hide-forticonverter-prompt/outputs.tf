output "stitch_name" {
  description = "Name of the automation stitch bound to the built-in `Reboot` trigger. Read back from the resource; matches the `stitch_name` input."
  value       = fortios_system_automationstitch.this.name
}

output "action_name" {
  description = "Name of the `cli-script` automation action that runs the FortiConverter prompt-hiding diagnose command. Read back from the resource; matches the `action_name` input."
  value       = fortios_system_automationaction.this.name
}
