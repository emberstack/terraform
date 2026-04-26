# =============================================================================
# IPv4 CIDR MATH
# =============================================================================
# A /32 is a single host, so the usual "network + broadcast are unusable"
# arithmetic (2^host_bits - 2) underflows to -1 and every usable-host output
# fails with `cidrhost: prefix of 32 does not accommodate a host numbered 1`.
# `single_host` special-cases it: the one address is reported as the usable
# first, last and range.
#
# /31 is deliberately left as-is (usable_count 0, first/last still emitted).
# Changing it to RFC 3021 semantics would alter values callers already consume.
# =============================================================================

locals {
  octet_bits = {
    "0"   = 0, "128" = 1, "192" = 2, "224" = 3, "240" = 4,
    "248" = 5, "252" = 6, "254" = 7, "255" = 8
  }

  netmask_octets = split(".", var.netmask)
  ip_octets      = split(".", var.ip)

  prefix_length = sum([for o in local.netmask_octets : local.octet_bits[o]])
  host_bits     = 32 - local.prefix_length
  single_host   = local.prefix_length == 32
  host_count    = local.single_host ? 1 : pow(2, local.host_bits) - 2

  network_cidr = "${cidrhost("${var.ip}/${local.prefix_length}", 0)}/${local.prefix_length}"

  usable_first = local.single_host ? cidrhost(local.network_cidr, 0) : cidrhost(local.network_cidr, 1)
  usable_last  = local.single_host ? cidrhost(local.network_cidr, 0) : cidrhost(local.network_cidr, local.host_count)
  range_last   = local.single_host ? cidrhost(local.network_cidr, 0) : cidrhost(local.network_cidr, local.host_count + 1)
}
