variable "interface" {
  description = "Name of the system interface this DHCP server listens on."
  type        = string
}

variable "default_gateway" {
  description = "Gateway address handed to clients in the lease. Normally the FortiGate's own address on `interface`."
  type        = string
}

variable "netmask" {
  description = "Subnet mask handed to clients, in dotted-quad form."
  type        = string
  default     = "255.255.255.0"
}

variable "dns_service" {
  description = <<-EOT
    Which DNS servers clients are given: `local` (the FortiGate itself),
    `default` (the device's system DNS servers), or `specify` (the
    `dns_server1-3` fields).

    This module never sets `dns_server1-3` and ignores drift on them, so
    `specify` has nothing to point at here — use `local` or `default`.
  EOT
  type        = string
  default     = "local"
}

variable "ntp_service" {
  description = <<-EOT
    Which NTP servers clients are given: `local` (the FortiGate itself),
    `default` (the device's system NTP servers), or `specify` (the
    `ntp_server1-3` fields).

    As with `dns_service`, this module never sets `ntp_server1-3` and ignores
    drift on them, so `specify` has nothing to point at here.
  EOT
  type        = string
  default     = "local"
}

variable "lease_time" {
  description = "Lease duration in seconds. Defaults to `604800` (7 days). `0` means unlimited."
  type        = number
  default     = 604800
}

variable "status" {
  description = "Whether the DHCP server hands out leases. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "ip_ranges" {
  description = <<-EOT
    Address pools the server allocates from, emitted as `ip_range` blocks in
    list order. Required — a DHCP server with no range has nothing to hand out.

    - `id` — range identifier, unique within this server.
    - `start_ip` — first address in the pool, inclusive.
    - `end_ip` — last address in the pool, inclusive.
  EOT
  type = list(object({
    id       = number
    start_ip = string
    end_ip   = string
  }))
}

variable "vci_strings" {
  description = <<-EOT
    Vendor Class Identifier strings to match against. **These are inert unless
    `vci_match` is also set to `enable`** — FortiOS stores the strings but never
    evaluates them while vci-match is disabled, which is the device default.
  EOT
  type        = list(string)
  default     = []
  nullable    = false
}

variable "vci_match" {
  description = <<-EOT
    Whether FortiOS evaluates `vci_strings` when handing out leases: `enable` or
    `disable`. Defaults to `null`, meaning the module does not manage the setting
    and whatever is on the device is left alone.

    ⚠️ Setting this to `enable` makes the DHCP server serve **only** clients whose
    Vendor Class Identifier matches one of `vci_strings`. Enabling it on a server
    that is already handing out leases will stop it answering every client that
    does not match. Set it deliberately, not as a cleanup.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.vci_match == null || contains(["enable", "disable"], coalesce(var.vci_match, "enable"))
    error_message = "vci_match must be either \"enable\" or \"disable\"."
  }
}

variable "reserved_addresses" {
  description = <<-EOT
    MAC-to-IP reservations, emitted as `reserved_address` blocks in list order.

    - `id` — reservation identifier, unique within this server.
    - `ip` — address always handed to that MAC. Reservations are not required to
      fall inside `ip_ranges`, but they must be on the server's subnet.
    - `mac` — client MAC address the reservation binds to.
    - `description` — free-text label stored on the reservation.
  EOT
  type = list(object({
    id          = number
    ip          = string
    mac         = string
    description = optional(string, "")
  }))
  default = []
}
