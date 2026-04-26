output "id" {
  description = "Numeric FortiOS table ID of the domain filter list. Pass this to a DNS filter profile's `domain_filter_table` to attach the list."
  value       = fortios_dnsfilter_domainfilter.this.fosid
}

output "name" {
  description = "Name of the domain filter list."
  value       = fortios_dnsfilter_domainfilter.this.name
}
