output "resource_id" {
  description = "Resource ID of the BGP connection."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the BGP connection."
  value       = azapi_resource.this.name
}

output "peer_asn" {
  description = "ASN of the peer NVA (echoes `var.peer_asn`)."
  value       = var.peer_asn
}

output "peer_ip" {
  description = "IP address of the peer NVA (echoes `var.peer_ip`)."
  value       = var.peer_ip
}

output "connection_state" {
  description = "BGP session state as ARM reports it (e.g. `Connected`). Read at refresh, so it reflects the session as of the last plan or apply. Null during an import, before the first refresh."
  value       = try(azapi_resource.this.output.connection_state, null)
}
