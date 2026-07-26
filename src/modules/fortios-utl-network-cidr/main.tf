# =============================================================================
# IPv4 CIDR MATH
# =============================================================================
# Two prefixes do not follow the usual "network and broadcast are unusable"
# arithmetic, and both are special-cased by offset rather than by branching on
# each value:
#
#   /32 — a single host. 2^host_bits - 2 underflows to -1 and every usable-host
#         value fails with `cidrhost: prefix of 32 does not accommodate a host
#         numbered 1`. The one address is the usable first, last and range.
#   /31 — a point-to-point link (RFC 3021). There is no network or broadcast
#         address, so both addresses are usable: count 2, first .0, last .1.
#         The full range is the same pair.
#
# `range_offset` is why /31 needs its own branch rather than falling through:
# host_count + 1 would be 3, and a /31 only has hosts 0 and 1.
# =============================================================================

locals {
  octet_bits = {
    "0"   = 0, "128" = 1, "192" = 2, "224" = 3, "240" = 4,
    "248" = 5, "252" = 6, "254" = 7, "255" = 8
  }

  netmask_octets = split(".", var.netmask)
  ip_octets      = split(".", var.ip)

  prefix_length  = sum([for o in local.netmask_octets : local.octet_bits[o]])
  host_bits      = 32 - local.prefix_length
  single_host    = local.prefix_length == 32
  point_to_point = local.prefix_length == 31
  host_count     = local.single_host ? 1 : local.point_to_point ? 2 : pow(2, local.host_bits) - 2

  network_cidr = "${cidrhost("${var.ip}/${local.prefix_length}", 0)}/${local.prefix_length}"

  first_offset = local.single_host || local.point_to_point ? 0 : 1
  last_offset  = local.single_host ? 0 : local.point_to_point ? 1 : local.host_count
  range_offset = local.single_host ? 0 : local.point_to_point ? 1 : local.host_count + 1

  usable_first = cidrhost(local.network_cidr, local.first_offset)
  usable_last  = cidrhost(local.network_cidr, local.last_offset)
  range_last   = cidrhost(local.network_cidr, local.range_offset)
}
