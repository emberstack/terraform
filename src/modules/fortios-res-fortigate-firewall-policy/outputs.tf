output "id" {
  description = "Terraform resource ID of the policy (the FortiOS policy ID as a string). Use it for `depends_on` wiring or state addressing."
  value       = fortios_firewall_policy.this.id
}

output "policyid" {
  description = "Numeric FortiOS `policyid` assigned to the policy — the value the device assigned when `var.policyid` was left null."
  value       = fortios_firewall_policy.this.policyid
}

output "name" {
  description = "Policy name as stored on the device."
  value       = fortios_firewall_policy.this.name
}
