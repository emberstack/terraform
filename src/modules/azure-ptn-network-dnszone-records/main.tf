# =============================================================================
# AZURE PUBLIC DNS RECORDS
# =============================================================================
# Works against any existing zone — this module's sibling `azure-res-network-dnszone`,
# an AVM-managed zone, or a hand-created one.
#
# Record sets carry their tags in `properties.metadata`, NOT in resource `tags`.
# They are not tracked resources and have no `location`.
#
# One resource per record type rather than one resource with a computed `type`:
# the per-type bodies have different shapes and a conditional returning them all
# cannot type-unify.
#
# The public DNS API capitalizes its record collections — `ARecords`, `NSRecords`,
# `TTL` — where the private DNS API does not. `caaRecords` is the lone exception
# and is genuinely lower-case; that is an ARM quirk, not a typo.
# =============================================================================

locals {
  a_records     = { for k, v in var.dns_zone_records : k => v if v.type == "A" }
  aaaa_records  = { for k, v in var.dns_zone_records : k => v if v.type == "AAAA" }
  caa_records   = { for k, v in var.dns_zone_records : k => v if v.type == "CAA" }
  cname_records = { for k, v in var.dns_zone_records : k => v if v.type == "CNAME" }
  mx_records    = { for k, v in var.dns_zone_records : k => v if v.type == "MX" }
  ns_records    = { for k, v in var.dns_zone_records : k => v if v.type == "NS" }
  ptr_records   = { for k, v in var.dns_zone_records : k => v if v.type == "PTR" }
  srv_records   = { for k, v in var.dns_zone_records : k => v if v.type == "SRV" }
  txt_records   = { for k, v in var.dns_zone_records : k => v if v.type == "TXT" }

  # `fqdn` is server-computed and only reachable through an explicit export.
  fqdn_export = { fqdn = "properties.fqdn" }
}

resource "azapi_resource" "a" {
  for_each = local.a_records

  name      = each.value.name
  parent_id = var.dns_zone_resource_id
  type      = "Microsoft.Network/dnsZones/A@2018-05-01"
  body = {
    properties = {
      ARecords = [for address in each.value.a_records : { ipv4Address = address }]
      metadata = merge(var.tags, each.value.tags)
      TTL      = each.value.ttl
    }
  }
  response_export_values = local.fqdn_export
}

resource "azapi_resource" "aaaa" {
  for_each = local.aaaa_records

  name      = each.value.name
  parent_id = var.dns_zone_resource_id
  type      = "Microsoft.Network/dnsZones/AAAA@2018-05-01"
  body = {
    properties = {
      AAAARecords = [for address in each.value.aaaa_records : { ipv6Address = address }]
      metadata    = merge(var.tags, each.value.tags)
      TTL         = each.value.ttl
    }
  }
  response_export_values = local.fqdn_export
}

resource "azapi_resource" "caa" {
  for_each = local.caa_records

  name      = each.value.name
  parent_id = var.dns_zone_resource_id
  type      = "Microsoft.Network/dnsZones/CAA@2018-05-01"
  body = {
    properties = {
      caaRecords = [for record in each.value.caa_records : {
        flags = record.flags
        tag   = record.tag
        value = record.value
      }]
      metadata = merge(var.tags, each.value.tags)
      TTL      = each.value.ttl
    }
  }
  response_export_values = local.fqdn_export
}

resource "azapi_resource" "cname" {
  for_each = local.cname_records

  name      = each.value.name
  parent_id = var.dns_zone_resource_id
  type      = "Microsoft.Network/dnsZones/CNAME@2018-05-01"
  body = {
    properties = {
      CNAMERecord = { cname = each.value.cname_record }
      metadata    = merge(var.tags, each.value.tags)
      TTL         = each.value.ttl
    }
  }
  response_export_values = local.fqdn_export
}

resource "azapi_resource" "mx" {
  for_each = local.mx_records

  name      = each.value.name
  parent_id = var.dns_zone_resource_id
  type      = "Microsoft.Network/dnsZones/MX@2018-05-01"
  body = {
    properties = {
      metadata = merge(var.tags, each.value.tags)
      MXRecords = [for record in each.value.mx_records : {
        exchange   = record.exchange
        preference = record.preference
      }]
      TTL = each.value.ttl
    }
  }
  response_export_values = local.fqdn_export
}

resource "azapi_resource" "ns" {
  for_each = local.ns_records

  name      = each.value.name
  parent_id = var.dns_zone_resource_id
  type      = "Microsoft.Network/dnsZones/NS@2018-05-01"
  body = {
    properties = {
      metadata  = merge(var.tags, each.value.tags)
      NSRecords = [for nameserver in each.value.ns_records : { nsdname = nameserver }]
      TTL       = each.value.ttl
    }
  }
  response_export_values = local.fqdn_export
}

resource "azapi_resource" "ptr" {
  for_each = local.ptr_records

  name      = each.value.name
  parent_id = var.dns_zone_resource_id
  type      = "Microsoft.Network/dnsZones/PTR@2018-05-01"
  body = {
    properties = {
      metadata   = merge(var.tags, each.value.tags)
      PTRRecords = [for host in each.value.ptr_records : { ptrdname = host }]
      TTL        = each.value.ttl
    }
  }
  response_export_values = local.fqdn_export
}

resource "azapi_resource" "srv" {
  for_each = local.srv_records

  name      = each.value.name
  parent_id = var.dns_zone_resource_id
  type      = "Microsoft.Network/dnsZones/SRV@2018-05-01"
  body = {
    properties = {
      metadata = merge(var.tags, each.value.tags)
      SRVRecords = [for record in each.value.srv_records : {
        port     = record.port
        priority = record.priority
        target   = record.target
        weight   = record.weight
      }]
      TTL = each.value.ttl
    }
  }
  response_export_values = local.fqdn_export
}

resource "azapi_resource" "txt" {
  for_each = local.txt_records

  name      = each.value.name
  parent_id = var.dns_zone_resource_id
  type      = "Microsoft.Network/dnsZones/TXT@2018-05-01"
  body = {
    properties = {
      metadata = merge(var.tags, each.value.tags)
      TTL      = each.value.ttl
      # ARM nests each TXT string in its own record as a single-element array.
      TXTRecords = [for value in each.value.txt_records : { value = [value] }]
    }
  }
  response_export_values = local.fqdn_export
}
