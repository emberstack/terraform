# `fqdn` is read through `try` because `terraform import` does not apply
# `response_export_values` — during an import the export is simply absent, and a
# bare reference would fail the whole evaluation.

output "private_dns_zone_records" {
  description = "Map of created records, keyed by the input map key. Each entry exposes `id`, `name`, `fqdn`, and `type`."
  value = merge(
    { for k, v in azapi_resource.a : k => { id = v.id, name = v.name, fqdn = try(v.output.fqdn, null), type = "A" } },
    { for k, v in azapi_resource.aaaa : k => { id = v.id, name = v.name, fqdn = try(v.output.fqdn, null), type = "AAAA" } },
    { for k, v in azapi_resource.cname : k => { id = v.id, name = v.name, fqdn = try(v.output.fqdn, null), type = "CNAME" } },
    { for k, v in azapi_resource.mx : k => { id = v.id, name = v.name, fqdn = try(v.output.fqdn, null), type = "MX" } },
    { for k, v in azapi_resource.ptr : k => { id = v.id, name = v.name, fqdn = try(v.output.fqdn, null), type = "PTR" } },
    { for k, v in azapi_resource.srv : k => { id = v.id, name = v.name, fqdn = try(v.output.fqdn, null), type = "SRV" } },
    { for k, v in azapi_resource.txt : k => { id = v.id, name = v.name, fqdn = try(v.output.fqdn, null), type = "TXT" } },
  )
}

output "private_dns_zone_records_by_type" {
  description = "Records grouped by type, each value a map of `{id, name, fqdn}` keyed by the input map key."
  value = {
    a     = { for k, v in azapi_resource.a : k => { id = v.id, name = v.name, fqdn = try(v.output.fqdn, null) } }
    aaaa  = { for k, v in azapi_resource.aaaa : k => { id = v.id, name = v.name, fqdn = try(v.output.fqdn, null) } }
    cname = { for k, v in azapi_resource.cname : k => { id = v.id, name = v.name, fqdn = try(v.output.fqdn, null) } }
    mx    = { for k, v in azapi_resource.mx : k => { id = v.id, name = v.name, fqdn = try(v.output.fqdn, null) } }
    ptr   = { for k, v in azapi_resource.ptr : k => { id = v.id, name = v.name, fqdn = try(v.output.fqdn, null) } }
    srv   = { for k, v in azapi_resource.srv : k => { id = v.id, name = v.name, fqdn = try(v.output.fqdn, null) } }
    txt   = { for k, v in azapi_resource.txt : k => { id = v.id, name = v.name, fqdn = try(v.output.fqdn, null) } }
  }
}
