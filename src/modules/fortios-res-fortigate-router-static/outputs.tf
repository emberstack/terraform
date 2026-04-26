output "id" {
  description = "Terraform resource ID of the static route, which is the FortiOS sequence number (mkey). Use it to reference or import the route."
  value       = fortios_router_static.this.id
}

output "seq_num" {
  description = "Sequence number FortiOS assigned to the route. Useful when `seq_num` was left `null` and the device picked the slot."
  value       = fortios_router_static.this.seq_num
}

output "dst" {
  description = "Destination prefix as stored on the FortiGate, in `<address> <netmask>` form."
  value       = fortios_router_static.this.dst
}

output "dstaddr" {
  description = "Firewall address or address group used as the route destination, if one was configured."
  value       = fortios_router_static.this.dstaddr
}

output "gateway" {
  description = "Next-hop gateway IP address as stored on the FortiGate."
  value       = fortios_router_static.this.gateway
}

output "device" {
  description = "Outgoing interface name the route resolves to."
  value       = fortios_router_static.this.device
}

output "distance" {
  description = "Administrative distance applied to the route."
  value       = fortios_router_static.this.distance
}
