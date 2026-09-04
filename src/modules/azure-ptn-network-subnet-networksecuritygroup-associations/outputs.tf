output "resource_ids" {
  description = "Map of association key → resource ID of the association (equals the parent subnet's resource ID)."
  value       = { for k, v in azapi_update_resource.this : k => v.id }
}

output "network_security_group_resource_ids" {
  description = "Map of association key → the network security group resource ID ARM holds on the subnet after the write, read back from the response rather than echoed from the input."
  value       = { for k, v in azapi_update_resource.this : k => try(v.output.properties.networkSecurityGroup.id, null) }
}

output "subnet_network_security_group_associations" {
  description = "The subnet → network-security-group associations managed by this module, as supplied."
  value       = var.subnet_network_security_group_associations
}
