output "ipv4_network" {
  description = "Network address in CIDR notation, e.g. `10.0.0.0/24`."
  value       = local.network_cidr
}

output "ipv4_prefix_length" {
  description = "Prefix length as a number, e.g. `24`."
  value       = local.prefix_length
}

output "ipv4_prefix" {
  description = "Prefix length with a leading slash, e.g. `/24`."
  value       = "/${local.prefix_length}"
}

output "ipv4_usable_count" {
  description = "Number of usable host addresses. `1` for a /32 (the address itself), `0` for a /31."
  value       = local.host_count
}

output "ipv4_usable_first" {
  description = "First usable host address. For a /32 this is the address itself."
  value       = local.usable_first
}

output "ipv4_usable_last" {
  description = "Last usable host address. For a /32 this is the address itself."
  value       = local.usable_last
}

output "ipv4_usable_range" {
  description = "Usable host range as `first-last`."
  value       = "${local.usable_first}-${local.usable_last}"
}

output "ipv4_range" {
  description = "Full network range as `network-broadcast`, inclusive of both."
  value       = "${cidrhost(local.network_cidr, 0)}-${local.range_last}"
}
