variable "primary" {
  description = "IP address of the primary DNS server the FortiGate resolves against."
  type        = string
}

variable "secondary" {
  description = "IP address of the secondary DNS server. Empty leaves only the primary configured."
  type        = string
  default     = ""
}

variable "protocol" {
  description = "Transport used for outbound DNS queries. One of `cleartext`, `dot` (DNS over TLS) or `doh` (DNS over HTTPS)."
  type        = string
  default     = "cleartext"
}

variable "ssl_certificate" {
  description = "Name of the local certificate used to validate the server when `protocol` is `dot` or `doh`. Ignored for `cleartext`."
  type        = string
  default     = "Fortinet_Factory"
}

# Legacy predecessor of `protocol`; modern FortiOS never stores it, so sending a
# value perpetually diffs. Null omits it — set `protocol` instead.
variable "dns_over_tls" {
  description = "Legacy DNS-over-TLS toggle (`enable`, `disable` or `enforce`), superseded by `protocol`. Leave `null` so the attribute is not sent — modern FortiOS does not store it and any value causes a perpetual diff."
  type        = string
  default     = null
}

variable "domains" {
  description = "Local domain search suffixes appended to unqualified lookups. Each entry becomes one `domain` block on the resource; empty list configures none."
  type        = list(string)
  default     = []
}
