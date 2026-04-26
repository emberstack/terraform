# =============================================================================
# system/dns-database — a DNS zone hosted on the FortiGate's internal resolver.
# =============================================================================
# One zone per leaf. Records live in `dns_entries` (map keyed by
# "<hostname>:<TYPE>" so alpha-sort groups records per hostname and the type
# suffix prevents key collisions when adding AAAA / MX / TXT next to existing
# A records). FortiOS uses numeric `id` as the sub-mkey — keep the per-entry
# `id` field stable across edits to avoid record re-numbering churn.
# =============================================================================

variable "name" {
  description = "Zone mkey (e.g. 'example.com'). Usually equals `domain`."
  type        = string
}

variable "status" {
  description = "enable | disable. Zone-wide on/off."
  type        = string
  default     = "enable"
}

variable "type" {
  description = "primary | secondary | shadow. 'primary' = this FortiGate owns the zone; 'shadow' = no zone-transfer behavior, hosted only for forwarding."
  type        = string
  default     = "primary"
}

variable "view" {
  description = "shadow | public. 'shadow' = only served to interfaces with dns_server enabled; 'public' = served to all."
  type        = string
  default     = "shadow"
}

variable "domain" {
  description = "DNS domain name the zone is authoritative for (e.g. 'example.com')."
  type        = string
}

variable "ttl" {
  description = "Zone default TTL (seconds). Per-record TTL of 0 inherits this."
  type        = number
  default     = 30
}

variable "authoritative" {
  description = "enable | disable. Whether the FortiGate sets the AA (Authoritative Answer) bit in responses."
  type        = string
  default     = "disable"
}

variable "primary_name" {
  description = "SOA primary nameserver short name."
  type        = string
  default     = "dns"
}

variable "contact" {
  description = "SOA contact (e.g. 'admin' becomes admin.<zone> in SOA record)."
  type        = string
  default     = "admin"
}

variable "forwarder" {
  description = "Space-separated list of upstream resolver IPs. Empty = no forwarding."
  type        = string
  default     = ""
}

variable "source_ip" {
  description = "Source IP for queries to forwarders. 0.0.0.0 = auto."
  type        = string
  default     = "0.0.0.0"
}

variable "dns_entries" {
  description = <<-EOT
    Records served by this zone. Map keyed by "<hostname>:<TYPE>" — alpha
    sort groups records per hostname; the :TYPE suffix prevents collisions
    when the same hostname needs multiple record types (A + AAAA, A + MX,
    A + TXT, etc.).

    Per-entry fields:
      id             — numeric sub-mkey. FortiOS-assigned on first create;
                       preserve across edits to avoid record re-numbering.
      type           — A | AAAA | CNAME | MX | NS | SOA | PTR | TXT | SRV
      hostname       — short hostname (not the FQDN)
      ip             — for A / AAAA / PTR
      canonical_name — for CNAME (full FQDN of the target)
      preference     — for MX / SRV (priority)
      ttl            — 0 = inherit zone ttl
      status         — enable | disable
  EOT
  type = map(object({
    id             = number
    type           = string
    hostname       = string
    ip             = optional(string, "0.0.0.0")
    canonical_name = optional(string, "")
    preference     = optional(number, 10)
    ttl            = optional(number, 0)
    status         = optional(string, "enable")
  }))
  default = {}
}
