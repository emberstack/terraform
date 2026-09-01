output "disk_resource_id" {
  description = "Resource ID of the OS disk that was patched, resolved from the virtual machine."
  value       = local.os_disk_resource_id
}

output "public_network_access" {
  description = "Public network access on the OS disk as ARM reported it after the write."
  value       = try(azapi_update_resource.os_disk.output.properties.publicNetworkAccess, null)
}

output "network_access_policy" {
  description = "Network access policy on the OS disk as ARM reported it after the write."
  value       = try(azapi_update_resource.os_disk.output.properties.networkAccessPolicy, null)
}
