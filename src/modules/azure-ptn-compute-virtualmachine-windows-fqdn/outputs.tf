output "extension_id" {
  description = "Resource ID of the CustomScriptExtension that sets the primary DNS suffix."
  value       = azurerm_virtual_machine_extension.dns_suffix.id
}
