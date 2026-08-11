# =============================================================================
# AZURE PRIVATE DNS RECORDS
# =============================================================================
# Works against any existing zone — this module's sibling
# `azure-res-network-privatednszone`, an AVM-managed zone, or a hand-created one.
#
# Record sets carry their tags in `properties.metadata`, NOT in resource `tags`.
# They are not tracked resources and have no `location`.
#
# One resource per record type rather than one resource with a computed `type`:
# the per-type bodies have different shapes and a conditional returning them all
# cannot type-unify.
#
# Azure private DNS supports A, AAAA, CNAME, MX, PTR, SRV and TXT only — NS and
# CAA are rejected at validation time.
# =============================================================================

locals {
  a_records     = { for k, v in var.private_dns_zone_records : k => v if v.type == "A" }
  aaaa_records  = { for k, v in var.private_dns_zone_records : k => v if v.type == "AAAA" }
  cname_records = { for k, v in var.private_dns_zone_records : k => v if v.type == "CNAME" }
  mx_records    = { for k, v in var.private_dns_zone_records : k => v if v.type == "MX" }
  ptr_records   = { for k, v in var.private_dns_zone_records : k => v if v.type == "PTR" }
  srv_records   = { for k, v in var.private_dns_zone_records : k => v if v.type == "SRV" }
  txt_records   = { for k, v in var.private_dns_zone_records : k => v if v.type == "TXT" }

  # `fqdn` is server-computed and only reachable through an explicit export.
  fqdn_export = { fqdn = "properties.fqdn" }
}

resource "azapi_resource" "a" {
  for_each = local.a_records

  name      = each.value.name
  parent_id = var.private_dns_zone_resource_id
  type      = "Microsoft.Network/privateDnsZones/A@2024-06-01"
  body = {
    properties = {
      aRecords = [for address in each.value.a_records : { ipv4Address = address }]
      metadata = merge(var.tags, each.value.tags)
      ttl      = each.value.ttl
    }
  }
  response_export_values = local.fqdn_export
}

resource "azapi_resource" "aaaa" {
  for_each = local.aaaa_records

  name      = each.value.name
  parent_id = var.private_dns_zone_resource_id
  type      = "Microsoft.Network/privateDnsZones/AAAA@2024-06-01"
  body = {
    properties = {
      aaaaRecords = [for address in each.value.aaaa_records : { ipv6Address = address }]
      metadata    = merge(var.tags, each.value.tags)
      ttl         = each.value.ttl
    }
  }
  response_export_values = local.fqdn_export
}

resource "azapi_resource" "cname" {
  for_each = local.cname_records

  name      = each.value.name
  parent_id = var.private_dns_zone_resource_id
  type      = "Microsoft.Network/privateDnsZones/CNAME@2024-06-01"
  body = {
    properties = {
      cnameRecord = { cname = each.value.cname_record }
      metadata    = merge(var.tags, each.value.tags)
      ttl         = each.value.ttl
    }
  }
  response_export_values = local.fqdn_export
}

resource "azapi_resource" "mx" {
  for_each = local.mx_records

  name      = each.value.name
  parent_id = var.private_dns_zone_resource_id
  type      = "Microsoft.Network/privateDnsZones/MX@2024-06-01"
  body = {
    properties = {
      metadata = merge(var.tags, each.value.tags)
      mxRecords = [for record in each.value.mx_records : {
        exchange   = record.exchange
        preference = record.preference
      }]
      ttl = each.value.ttl
    }
  }
  response_export_values = local.fqdn_export
}

resource "azapi_resource" "ptr" {
  for_each = local.ptr_records

  name      = each.value.name
  parent_id = var.private_dns_zone_resource_id
  type      = "Microsoft.Network/privateDnsZones/PTR@2024-06-01"
  body = {
    properties = {
      metadata   = merge(var.tags, each.value.tags)
      ptrRecords = [for host in each.value.ptr_records : { ptrdname = host }]
      ttl        = each.value.ttl
    }
  }
  response_export_values = local.fqdn_export
}

resource "azapi_resource" "srv" {
  for_each = local.srv_records

  name      = each.value.name
  parent_id = var.private_dns_zone_resource_id
  type      = "Microsoft.Network/privateDnsZones/SRV@2024-06-01"
  body = {
    properties = {
      metadata = merge(var.tags, each.value.tags)
      srvRecords = [for record in each.value.srv_records : {
        port     = record.port
        priority = record.priority
        target   = record.target
        weight   = record.weight
      }]
      ttl = each.value.ttl
    }
  }
  response_export_values = local.fqdn_export
}

resource "azapi_resource" "txt" {
  for_each = local.txt_records

  name      = each.value.name
  parent_id = var.private_dns_zone_resource_id
  type      = "Microsoft.Network/privateDnsZones/TXT@2024-06-01"
  body = {
    properties = {
      metadata = merge(var.tags, each.value.tags)
      ttl      = each.value.ttl
      # ARM nests each TXT string in its own record as a single-element array.
      txtRecords = [for value in each.value.txt_records : { value = [value] }]
    }
  }
  response_export_values = local.fqdn_export
}
