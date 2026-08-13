# `fqdn` is read through `try` because `terraform import` does not apply
# `response_export_values` — during an import the export is simply absent, and a
# bare reference would fail the whole evaluation.

output "dns_zone_records" {
  description = "Map of created records, keyed by the input map key. Each entry exposes `fqdn`, `resource_id`, `name`, and `type`."
  value = merge(
    { for k, v in azapi_resource.a : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name, type = "A" } },
    { for k, v in azapi_resource.aaaa : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name, type = "AAAA" } },
    { for k, v in azapi_resource.caa : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name, type = "CAA" } },
    { for k, v in azapi_resource.cname : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name, type = "CNAME" } },
    { for k, v in azapi_resource.mx : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name, type = "MX" } },
    { for k, v in azapi_resource.ns : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name, type = "NS" } },
    { for k, v in azapi_resource.ptr : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name, type = "PTR" } },
    { for k, v in azapi_resource.srv : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name, type = "SRV" } },
    { for k, v in azapi_resource.txt : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name, type = "TXT" } },
  )
}

output "dns_zone_records_by_type" {
  description = "Records grouped by type, each value a map of `{fqdn, resource_id, name}` keyed by the input map key. Group keys use ARM's own casing (`A`, `AAAA`, `CNAME`, ...), matching the `type` field of `dns_zone_records`, so the two outputs compose."
  value = {
    A     = { for k, v in azapi_resource.a : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name } }
    AAAA  = { for k, v in azapi_resource.aaaa : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name } }
    CAA   = { for k, v in azapi_resource.caa : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name } }
    CNAME = { for k, v in azapi_resource.cname : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name } }
    MX    = { for k, v in azapi_resource.mx : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name } }
    NS    = { for k, v in azapi_resource.ns : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name } }
    PTR   = { for k, v in azapi_resource.ptr : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name } }
    SRV   = { for k, v in azapi_resource.srv : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name } }
    TXT   = { for k, v in azapi_resource.txt : k => { fqdn = try(v.output.fqdn, null), resource_id = v.id, name = v.name } }
  }
}
