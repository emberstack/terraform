# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "dns_zone_resource_id" {
  type        = string
  description = "ARM resource ID of the existing public DNS zone. Used directly as each record's `parent_id`."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.network/dnszones/[^/]+$", var.dns_zone_resource_id))
    error_message = "dns_zone_resource_id must be an ARM resource ID of an Azure public DNS zone."
  }
}

# -----------------------------------------------------------------------------
# Optional — records
# -----------------------------------------------------------------------------

variable "dns_zone_records" {
  type = map(object({
    name = string
    type = string
    ttl  = optional(number, 3600)
    tags = optional(map(string), {})

    a_records    = optional(list(string))
    aaaa_records = optional(list(string))
    # Null is the "this entry is not a CNAME" sentinel, validated below. A `""`
    # default would pass that check and send an empty `cname` to ARM.
    cname_record = optional(string, null)
    mx_records = optional(list(object({
      preference = number
      exchange   = string
    })))
    ns_records  = optional(list(string))
    ptr_records = optional(list(string))
    srv_records = optional(list(object({
      priority = number
      weight   = number
      port     = number
      target   = string
    })))
    txt_records = optional(list(string))
    caa_records = optional(list(object({
      flags = number
      tag   = string
      value = string
    })))
  }))
  default     = {}
  description = <<-EOT
    Map of DNS records to create in the zone, keyed by a stable identifier.

    Each entry's `type` selects which Azure resource is created and which type-specific
    field must be populated:

    - `A`     → `a_records`     (list of IPv4 addresses)
    - `AAAA`  → `aaaa_records`  (list of IPv6 addresses)
    - `CNAME` → `cname_record`  (single hostname)
    - `MX`    → `mx_records`    (list of `{preference, exchange}`)
    - `NS`    → `ns_records`    (list of nameserver hostnames)
    - `PTR`   → `ptr_records`   (list of hostnames)
    - `SRV`   → `srv_records`   (list of `{priority, weight, port, target}`)
    - `TXT`   → `txt_records`   (list of TXT string values)
    - `CAA`   → `caa_records`   (list of `{flags, tag, value}`)
  EOT

  validation {
    condition     = alltrue([for k, v in var.dns_zone_records : contains(["A", "AAAA", "CNAME", "MX", "NS", "PTR", "SRV", "TXT", "CAA"], v.type)])
    error_message = "Each record's `type` must be one of: A, AAAA, CNAME, MX, NS, PTR, SRV, TXT, CAA."
  }

  validation {
    condition = alltrue([
      for k, v in var.dns_zone_records : (
        v.type == "A" ? v.a_records != null && length(v.a_records) > 0 :
        v.type == "AAAA" ? v.aaaa_records != null && length(v.aaaa_records) > 0 :
        v.type == "CNAME" ? v.cname_record != null :
        v.type == "MX" ? v.mx_records != null && length(v.mx_records) > 0 :
        v.type == "NS" ? v.ns_records != null && length(v.ns_records) > 0 :
        v.type == "PTR" ? v.ptr_records != null && length(v.ptr_records) > 0 :
        v.type == "SRV" ? v.srv_records != null && length(v.srv_records) > 0 :
        v.type == "TXT" ? v.txt_records != null && length(v.txt_records) > 0 :
        v.type == "CAA" ? v.caa_records != null && length(v.caa_records) > 0 :
        false
      )
    ])
    error_message = "Each record must populate the type-specific field (e.g., `type = \"A\"` requires `a_records`; `type = \"CNAME\"` requires `cname_record`)."
  }
}

# -----------------------------------------------------------------------------
# Optional — metadata
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to merge into every record. Per-record `tags` win over these on key collisions."
}
