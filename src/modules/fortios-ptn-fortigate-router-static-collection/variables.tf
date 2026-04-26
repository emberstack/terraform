variable "routes" {
  description = <<-EOT
    Map of static routes to create, one `fortios_router_static` per entry. The map key is
    the Terraform address and the output key only — it is not sent to the FortiGate; the
    device-side identity is `seq_num`. Pick stable keys so removing one entry does not
    re-address the others.

    Per-entry fields:
      - `seq_num`    — route sequence number (mkey). Omit to let FortiOS assign the next free one.
      - `dst`        — destination subnet, e.g. `10.0.0.0 255.255.255.0`. Mutually exclusive with `dstaddr`.
      - `dstaddr`    — name of an existing firewall address/address-group used as the destination
                       instead of `dst`.
      - `gateway`    — next-hop IP address. Omit for interface-only (directly connected) routes.
      - `device`     — egress interface name.
      - `distance`   — administrative distance used to choose between routes to the same destination
                       (lower wins).
      - `priority`   — route priority used to break ties between routes of equal distance (lower wins).
      - `status`     — one of `enable` or `disable`.
      - `sdwan_zone` — SD-WAN zone name. When set, emits a `sdwan_zone` block with this name; when
                       null the block is omitted entirely and the route is not SD-WAN steered. Only a
                       single zone is supported by this module.
      - `comment`    — free-text comment stored on the route.
  EOT
  type = map(object({
    seq_num    = optional(number)
    dst        = optional(string)
    dstaddr    = optional(string)
    gateway    = optional(string)
    device     = optional(string)
    distance   = optional(number)
    priority   = optional(number)
    status     = optional(string)
    sdwan_zone = optional(string)
    comment    = optional(string)
  }))
  default = {}
}
