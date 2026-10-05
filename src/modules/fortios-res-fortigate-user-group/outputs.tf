output "id" {
  description = "Terraform resource ID of the user group (the group name as used by the FortiOS API)."
  value       = fortios_user_group.this.id
}

output "name" {
  description = "Name of the user group. Pass this to anything that references a user group by name, such as a firewall policy's `groups` or a VPN phase1 `authusrgrp`."
  value       = fortios_user_group.this.name
}
