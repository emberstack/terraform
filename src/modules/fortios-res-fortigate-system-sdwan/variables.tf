variable "status" {
  description = "Whether SD-WAN is enabled on the device. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "zones" {
  description = <<-EOT
    SD-WAN zones to create, keyed by an arbitrary stable identifier. Each entry
    emits one `zone` block. The map key is only the Terraform address — the zone
    on the device is named by `name`.

    - `name` — zone name, referenced by SD-WAN members and firewall policies.
  EOT
  type = map(object({
    name = string
  }))
  default = {}
}

variable "members" {
  description = <<-EOT
    SD-WAN member interfaces, emitted as `members` blocks in list order.

    - `seq_num` — member sequence number. This is the handle health checks and
      services reference, so keep it stable.
    - `interface` — name of the underlying system interface.
    - `gateway` — next-hop gateway for the member. `0.0.0.0` means no static
      gateway (e.g. the interface learns one from DHCP/PPPoE).
    - `status` — whether the member is in service. One of `enable` or `disable`.
    - `cost` — member cost used by cost-based selection. Lower wins.
    - `priority` — route priority for the member's default route. Lower wins.
  EOT
  type = list(object({
    seq_num   = number
    interface = string
    gateway   = optional(string, "0.0.0.0")
    status    = optional(string, "enable")
    cost      = optional(number, 0)
    priority  = optional(number, 1)
  }))
  default = []
}

variable "health_checks" {
  description = <<-EOT
    SD-WAN performance SLA health checks, emitted as `health_check` blocks in
    list order.

    - `name` — health check name.
    - `server` — probe targets. The module joins this list into the single
      space-separated string FortiOS expects, so pass one element per target.
    - `protocol` — probe protocol, e.g. `ping`, `http`, `tcp-echo`, `udp-echo`,
      `twamp`, `dns`.
    - `interval` — probe interval in milliseconds.
    - `failtime` — consecutive failed probes before the member is marked down.
    - `recoverytime` — consecutive successful probes before it is marked up again.
    - `update_static_route` — whether the health check withdraws the member's
      static route when it fails. One of `enable` or `disable`.
    - `members` — member `seq_num` values this check applies to. Empty means all
      SD-WAN members.
    - `sla` — SLA targets, each emitted as an `sla` block:
      - `id` — SLA identifier, referenced by SD-WAN rules.
      - `link_cost_factor` — space-separated list of metrics the SLA evaluates,
        drawn from `latency`, `jitter`, `packet-loss`, `mos`, `remote`, and
        `custom-profile-1`.
      - `latency_threshold` — maximum latency in milliseconds.
      - `jitter_threshold` — maximum jitter in milliseconds.
      - `packetloss_threshold` — maximum packet loss in percent.
      - `mos_threshold` — minimum Mean Opinion Score, as a decimal string.
      - `custom_profile_threshold` — threshold for the `custom-profile-1` factor.
      - `priority_in_sla` — route priority applied while the member meets the SLA.
      - `priority_out_sla` — route priority applied while it does not.
  EOT
  type = list(object({
    name                = string
    server              = list(string)
    protocol            = optional(string, "ping")
    interval            = optional(number, 500)
    failtime            = optional(number, 5)
    recoverytime        = optional(number, 5)
    update_static_route = optional(string, "enable")
    members             = optional(list(number), [])
    sla = optional(list(object({
      id                       = number
      link_cost_factor         = optional(string, "latency jitter packet-loss custom-profile-1")
      latency_threshold        = optional(number, 250)
      jitter_threshold         = optional(number, 50)
      packetloss_threshold     = optional(number, 5)
      mos_threshold            = optional(string, "3.6")
      custom_profile_threshold = optional(number, 0)
      priority_in_sla          = optional(number, 0)
      priority_out_sla         = optional(number, 0)
    })), [])
  }))
  default = []
}

variable "services" {
  description = <<-EOT
    SD-WAN rules (FortiOS calls them services), emitted as `service` blocks in
    list order.

    - `id` — rule ID. Also determines match order on the device.
    - `name` — rule name.
    - `mode` — member selection strategy, e.g. `manual`, `auto`, `priority`,
      `sla`, or `load-balance`. `manual` follows `priority_members` order.
    - `dst` — destination firewall address names the rule matches.
    - `src` — source firewall address names the rule matches.
    - `priority_members` — member `seq_num` values in preference order.
  EOT
  type = list(object({
    id               = number
    name             = string
    mode             = optional(string, "manual")
    dst              = optional(list(string), ["all"])
    src              = optional(list(string), ["all"])
    priority_members = optional(list(number), [])
  }))
  default = []
}
