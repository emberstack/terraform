# `fqdn` is read through `try` because `terraform import` does not apply
# `response_export_values` — during an import the export is simply absent, and a
# bare reference would fail the whole evaluation.

output "dns_zone_records" {
  description = "Map of created records, keyed by the input map key. Each entry exposes `fqdn`, `id`, `name`, and `type`."
  value = merge(
    { for k, v in azapi_resource.a : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name, type = "A" } },
    { for k, v in azapi_resource.aaaa : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name, type = "AAAA" } },
    { for k, v in azapi_resource.caa : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name, type = "CAA" } },
    { for k, v in azapi_resource.cname : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name, type = "CNAME" } },
    { for k, v in azapi_resource.mx : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name, type = "MX" } },
    { for k, v in azapi_resource.ns : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name, type = "NS" } },
    { for k, v in azapi_resource.ptr : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name, type = "PTR" } },
    { for k, v in azapi_resource.srv : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name, type = "SRV" } },
    { for k, v in azapi_resource.txt : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name, type = "TXT" } },
  )
}

output "dns_zone_records_by_type" {
  description = "Records grouped by type, each value a map of `{fqdn, id, name}` keyed by the input map key."
  value = {
    a     = { for k, v in azapi_resource.a : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name } }
    aaaa  = { for k, v in azapi_resource.aaaa : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name } }
    caa   = { for k, v in azapi_resource.caa : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name } }
    cname = { for k, v in azapi_resource.cname : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name } }
    mx    = { for k, v in azapi_resource.mx : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name } }
    ns    = { for k, v in azapi_resource.ns : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name } }
    ptr   = { for k, v in azapi_resource.ptr : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name } }
    srv   = { for k, v in azapi_resource.srv : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name } }
    txt   = { for k, v in azapi_resource.txt : k => { fqdn = try(v.output.fqdn, null), id = v.id, name = v.name } }
  }
}
