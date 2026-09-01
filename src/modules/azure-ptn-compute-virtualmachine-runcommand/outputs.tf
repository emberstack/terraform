output "resource_id" {
  description = "Resource ID of the run command on the VM."
  value       = azapi_resource.run_command.id
}

output "name" {
  description = "Name of the run command resource on the VM."
  value       = azapi_resource.run_command.name
}

# Provisioning state, not script state. It says whether the platform delivered
# and ran the command; the script's own exit code and captured output live in the
# instance view, which a plain GET does not return — reading it needs
# `$expand=instanceView`, so use `az vm run-command show --expand instanceView`
# rather than expecting it here.
#
# With treat_failure_as_deployment_failure at its default this is effectively
# always "Succeeded", because anything else has already failed the apply. It
# earns its keep when async_execution is on, where the apply returns before the
# script finishes.
output "provisioning_state" {
  description = "Provisioning state of the run command as ARM reported it on write — whether the platform ran the command, not whether the script succeeded."
  value       = try(azapi_resource.run_command.output.properties.provisioningState, null)
}

