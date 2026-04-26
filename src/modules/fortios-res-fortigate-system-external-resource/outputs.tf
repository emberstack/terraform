output "id" {
  description = "Terraform resource ID of the external resource entry, which is its name."
  value       = fortios_system_externalresource.this.id
}

output "name" {
  description = "Name of the external resource, read back from the resource. Use this to reference the feed from address groups, web filter profiles or policies."
  value       = fortios_system_externalresource.this.name
}

output "type" {
  description = "Effective feed type (`category`, `address`, `domain`, `malware`, ...), read back from the resource."
  value       = fortios_system_externalresource.this.type
}

output "category" {
  description = "Effective user-resource category ID the feed's entries are filed under, read back from the resource."
  value       = fortios_system_externalresource.this.category
}
