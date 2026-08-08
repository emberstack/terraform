output "private_dns_zone_records" {
  description = "Map of created records, keyed by the input map key. Each entry exposes `id`, `name`, `fqdn`, and `type`."
  value = merge(
    { for k, v in azapi_resource.a : k => { id = v.id, name = v.name, fqdn = v.output.fqdn, type = "A" } },
    { for k, v in azapi_resource.aaaa : k => { id = v.id, name = v.name, fqdn = v.output.fqdn, type = "AAAA" } },
    { for k, v in azapi_resource.cname : k => { id = v.id, name = v.name, fqdn = v.output.fqdn, type = "CNAME" } },
    { for k, v in azapi_resource.mx : k => { id = v.id, name = v.name, fqdn = v.output.fqdn, type = "MX" } },
    { for k, v in azapi_resource.ptr : k => { id = v.id, name = v.name, fqdn = v.output.fqdn, type = "PTR" } },
    { for k, v in azapi_resource.srv : k => { id = v.id, name = v.name, fqdn = v.output.fqdn, type = "SRV" } },
    { for k, v in azapi_resource.txt : k => { id = v.id, name = v.name, fqdn = v.output.fqdn, type = "TXT" } },
  )
}

output "private_dns_zone_records_by_type" {
  description = "Records grouped by type, each value a map of `{id, name, fqdn}` keyed by the input map key."
  value = {
    a     = { for k, v in azapi_resource.a : k => { id = v.id, name = v.name, fqdn = v.output.fqdn } }
    aaaa  = { for k, v in azapi_resource.aaaa : k => { id = v.id, name = v.name, fqdn = v.output.fqdn } }
    cname = { for k, v in azapi_resource.cname : k => { id = v.id, name = v.name, fqdn = v.output.fqdn } }
    mx    = { for k, v in azapi_resource.mx : k => { id = v.id, name = v.name, fqdn = v.output.fqdn } }
    ptr   = { for k, v in azapi_resource.ptr : k => { id = v.id, name = v.name, fqdn = v.output.fqdn } }
    srv   = { for k, v in azapi_resource.srv : k => { id = v.id, name = v.name, fqdn = v.output.fqdn } }
    txt   = { for k, v in azapi_resource.txt : k => { id = v.id, name = v.name, fqdn = v.output.fqdn } }
  }
}
