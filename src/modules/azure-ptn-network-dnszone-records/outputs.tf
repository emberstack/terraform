output "dns_zone_records" {
  description = "Map of created records, keyed by the input map key. Each entry exposes `id`, `name`, `fqdn`, and `type`."
  value = merge(
    { for k, v in azurerm_dns_a_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn, type = "A" } },
    { for k, v in azurerm_dns_aaaa_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn, type = "AAAA" } },
    { for k, v in azurerm_dns_cname_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn, type = "CNAME" } },
    { for k, v in azurerm_dns_mx_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn, type = "MX" } },
    { for k, v in azurerm_dns_ns_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn, type = "NS" } },
    { for k, v in azurerm_dns_ptr_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn, type = "PTR" } },
    { for k, v in azurerm_dns_srv_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn, type = "SRV" } },
    { for k, v in azurerm_dns_txt_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn, type = "TXT" } },
    { for k, v in azurerm_dns_caa_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn, type = "CAA" } },
  )
}

output "dns_zone_records_by_type" {
  description = "Records grouped by type, each value a map of `{id, name, fqdn}` keyed by the input map key."
  value = {
    a     = { for k, v in azurerm_dns_a_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn } }
    aaaa  = { for k, v in azurerm_dns_aaaa_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn } }
    cname = { for k, v in azurerm_dns_cname_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn } }
    mx    = { for k, v in azurerm_dns_mx_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn } }
    ns    = { for k, v in azurerm_dns_ns_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn } }
    ptr   = { for k, v in azurerm_dns_ptr_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn } }
    srv   = { for k, v in azurerm_dns_srv_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn } }
    txt   = { for k, v in azurerm_dns_txt_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn } }
    caa   = { for k, v in azurerm_dns_caa_record.this : k => { id = v.id, name = v.name, fqdn = v.fqdn } }
  }
}
