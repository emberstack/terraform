variable "fosid" {
  description = "Numeric FortiOS table ID for the domain filter list. Leave `null` to let FortiOS allocate the next free ID; set it explicitly when a DNS filter profile has to reference this list by number via `domain_filter_table`."
  type        = number
  default     = null
}

variable "name" {
  description = "Name of the domain filter list as shown on the FortiGate."
  type        = string
}

variable "comment" {
  description = "Free-text comment stored on the domain filter list."
  type        = string
  default     = ""
}

variable "entries" {
  description = <<-EOT
    Ordered list of domain filter entries. Each entry renders one `entries`
    block on the resource:

    - `id`     — numeric entry ID, unique within the list; also its evaluation order.
    - `domain` — the domain pattern to match, interpreted according to `type`.
    - `type`   — how `domain` is matched: `simple`, `regex` or `wildcard`.
    - `action` — what to do on match: `block`, `allow` or `monitor`.
    - `status` — whether the entry is active: `enable` or `disable`.

    An empty list creates the domain filter list with no entries.
  EOT
  type = list(object({
    id     = number
    domain = string
    type   = optional(string, "simple")
    action = optional(string, "allow")
    status = optional(string, "enable")
  }))
  default = []
}
