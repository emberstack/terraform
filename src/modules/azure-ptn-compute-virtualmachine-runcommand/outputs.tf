output "resource_id" {
  description = "Resource ID of the run command on the VM."
  value       = azapi_resource.run_command.id
}

output "name" {
  description = "Name of the run command resource on the VM."
  value       = azapi_resource.run_command.name
}
