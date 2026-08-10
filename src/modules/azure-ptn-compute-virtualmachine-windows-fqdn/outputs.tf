output "extension_id" {
  description = "Resource ID of the CustomScriptExtension that sets the primary DNS suffix."
  value       = azapi_resource.dns_suffix.id
}
