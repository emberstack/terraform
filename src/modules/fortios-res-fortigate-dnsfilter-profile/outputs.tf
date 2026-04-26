output "id" {
  description = "Terraform resource ID of the DNS filter profile. For this provider it is the FortiOS mkey, i.e. the same value as `name`."
  value       = fortios_dnsfilter_profile.this.id
}

output "name" {
  description = "Name of the DNS filter profile. Use this as the `dnsfilter_profile` value on firewall policies."
  value       = fortios_dnsfilter_profile.this.name
}
