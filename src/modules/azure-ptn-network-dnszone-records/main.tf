# =============================================================================
# AZURE PUBLIC DNS RECORDS
# =============================================================================
# Creates records in an existing public DNS zone. Records are type-discriminated
# via the `type` field on each entry — one Azure resource per type.
#
# Can be used standalone against any existing zone (AVM-managed, manually
# created, etc.) — it does not require the parent `azure-res-network-dnszone`
# module.
# =============================================================================

locals {
  zone_id_parts       = split("/", var.dns_zone_resource_id)
  zone_resource_group = local.zone_id_parts[4]
  zone_name           = local.zone_id_parts[8]

  a_records     = { for k, v in var.dns_zone_records : k => v if v.type == "A" }
  aaaa_records  = { for k, v in var.dns_zone_records : k => v if v.type == "AAAA" }
  cname_records = { for k, v in var.dns_zone_records : k => v if v.type == "CNAME" }
  mx_records    = { for k, v in var.dns_zone_records : k => v if v.type == "MX" }
  ns_records    = { for k, v in var.dns_zone_records : k => v if v.type == "NS" }
  ptr_records   = { for k, v in var.dns_zone_records : k => v if v.type == "PTR" }
  srv_records   = { for k, v in var.dns_zone_records : k => v if v.type == "SRV" }
  txt_records   = { for k, v in var.dns_zone_records : k => v if v.type == "TXT" }
  caa_records   = { for k, v in var.dns_zone_records : k => v if v.type == "CAA" }
}

resource "azurerm_dns_a_record" "this" {
  for_each = local.a_records

  name                = each.value.name
  zone_name           = local.zone_name
  resource_group_name = local.zone_resource_group
  ttl                 = each.value.ttl
  records             = each.value.a_records
  tags                = merge(var.tags, each.value.tags)
}

resource "azurerm_dns_aaaa_record" "this" {
  for_each = local.aaaa_records

  name                = each.value.name
  zone_name           = local.zone_name
  resource_group_name = local.zone_resource_group
  ttl                 = each.value.ttl
  records             = each.value.aaaa_records
  tags                = merge(var.tags, each.value.tags)
}

resource "azurerm_dns_cname_record" "this" {
  for_each = local.cname_records

  name                = each.value.name
  zone_name           = local.zone_name
  resource_group_name = local.zone_resource_group
  ttl                 = each.value.ttl
  record              = each.value.cname_record
  tags                = merge(var.tags, each.value.tags)
}

resource "azurerm_dns_mx_record" "this" {
  for_each = local.mx_records

  name                = each.value.name
  zone_name           = local.zone_name
  resource_group_name = local.zone_resource_group
  ttl                 = each.value.ttl
  tags                = merge(var.tags, each.value.tags)

  dynamic "record" {
    for_each = each.value.mx_records
    content {
      preference = record.value.preference
      exchange   = record.value.exchange
    }
  }
}

resource "azurerm_dns_ns_record" "this" {
  for_each = local.ns_records

  name                = each.value.name
  zone_name           = local.zone_name
  resource_group_name = local.zone_resource_group
  ttl                 = each.value.ttl
  records             = each.value.ns_records
  tags                = merge(var.tags, each.value.tags)
}

resource "azurerm_dns_ptr_record" "this" {
  for_each = local.ptr_records

  name                = each.value.name
  zone_name           = local.zone_name
  resource_group_name = local.zone_resource_group
  ttl                 = each.value.ttl
  records             = each.value.ptr_records
  tags                = merge(var.tags, each.value.tags)
}

resource "azurerm_dns_srv_record" "this" {
  for_each = local.srv_records

  name                = each.value.name
  zone_name           = local.zone_name
  resource_group_name = local.zone_resource_group
  ttl                 = each.value.ttl
  tags                = merge(var.tags, each.value.tags)

  dynamic "record" {
    for_each = each.value.srv_records
    content {
      priority = record.value.priority
      weight   = record.value.weight
      port     = record.value.port
      target   = record.value.target
    }
  }
}

resource "azurerm_dns_txt_record" "this" {
  for_each = local.txt_records

  name                = each.value.name
  zone_name           = local.zone_name
  resource_group_name = local.zone_resource_group
  ttl                 = each.value.ttl
  tags                = merge(var.tags, each.value.tags)

  dynamic "record" {
    for_each = each.value.txt_records
    content {
      value = record.value
    }
  }
}

resource "azurerm_dns_caa_record" "this" {
  for_each = local.caa_records

  name                = each.value.name
  zone_name           = local.zone_name
  resource_group_name = local.zone_resource_group
  ttl                 = each.value.ttl
  tags                = merge(var.tags, each.value.tags)

  dynamic "record" {
    for_each = each.value.caa_records
    content {
      flags = record.value.flags
      tag   = record.value.tag
      value = record.value.value
    }
  }
}
