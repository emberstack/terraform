variable "update_if_exist" {
  description = "If true, an existing wtp-profile with the same name is updated in place instead of erroring on duplicate-mkey."
  type        = bool
  default     = true
}

variable "name" {
  description = "Name of the AP profile. This is the FortiOS mkey and the value a managed AP references via its `wtp_profile` field."
  type        = string
}

variable "comment" {
  description = "Free-text comment stored on the profile."
  type        = string
  default     = ""
}

variable "ap_country" {
  description = "Per-profile regulatory domain override. Default '--' inherits from wireless-controller/settings.country (single source of truth). Only set explicitly when this profile lives in a different country than the rest of the deployment."
  type        = string
  default     = "--"
}

variable "allowaccess" {
  description = "Space-separated list of management protocols permitted on APs using this profile, e.g. `https ssh snmp`. An individual AP can replace this list by setting `override_allowaccess` on its own `wtp` entry."
  type        = string
  default     = "https ssh snmp"
}

variable "ap_handoff" {
  description = "AP handoff — lets the controller steer clients from a loaded AP to a neighbouring one. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "frequency_handoff" {
  description = "Frequency handoff — lets the controller move clients to a different band or channel on the same AP. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "handoff_sta_thresh" {
  description = "Client-count threshold on a radio above which AP handoff starts steering clients away. Only takes effect when `ap_handoff` is `enable`."
  type        = number
  default     = 55
}

variable "wan_port_mode" {
  description = "Role of the AP's WAN port. `wan-lan` lets the port serve as both uplink and a wired LAN port; `wan-only` restricts it to the controller uplink."
  type        = string
  default     = "wan-lan"
}

variable "led_state" {
  description = "AP body LED. 'enable' to keep status LEDs on, 'disable' to dark the AP."
  type        = string
  default     = "enable"
}

variable "poe_mode" {
  description = "PoE-out on AP LAN port. 'auto' | '8023af' | '8023at' | 'power-source-equipment'."
  type        = string
  default     = "auto"
}

variable "platform" {
  description = <<-EOT
    AP platform spec.
    - type:   chassis SKU string (e.g. '441K', '431G').
    - mode:   single-5G / dual-5G — most tri-band APs are single-5G.
    - ddscan: 'enable' = chassis uses a dedicated path for background scanning
              (default on F-series). When enabled, per-radio wids_profile
              binding is hidden from the UI and silently rejected by the API.
              Set 'disable' to allow per-radio wids_profile assignment.
              NOTE: FAP441K (Wi-Fi 7) firmware-locks ddscan=enable regardless
              of what's written; explicit 'enable' here just documents reality.
  EOT
  type = object({
    type   = string
    mode   = optional(string)
    ddscan = optional(string)
  })
}

variable "lan" {
  description = <<-EOT
    Optional LAN port behavior on the AP body. APs with multiple wired LAN
    ports (e.g. FAP441K has port + port1) expose each port independently.
    port_mode values: offline | nat-to-wan | bridge-to-wan | bridge-to-ssid.
    port_ssid is required when port_mode = bridge-to-ssid.
  EOT
  type = object({
    port_mode  = optional(string)
    port_ssid  = optional(string)
    port1_mode = optional(string)
    port1_ssid = optional(string)
  })
  default = null
}

# Per-radio config
variable "radio_1" {
  description = <<-EOT
    Configuration for the AP's first radio. `null` (the default) omits the
    `radio_1` block entirely, leaving whatever FortiOS defaults the chassis has.
    - mode:                 radio role — `ap` (serving), `monitor`, `sniffer` or
                            `disabled`. Only `ap` radios transmit client traffic.
    - band:                 band/PHY selector, e.g. `802.11ax-5G`, `802.11ax-2G`.
                            Accepted values depend on chassis and FortiOS version.
    - channel:              list of channel numbers the radio may use. Rendered as
                            one `channel` block per entry, stringified. Empty list
                            leaves channel selection to FortiOS / DARRP.
    - channel_bonding:      channel width, e.g. `20MHz`, `40MHz`, `80MHz`, `160MHz`.
                            Valid widths depend on band and chassis.
    - power_level:          fixed transmit power, as a percentage of the radio
                            maximum. Used when `auto_power_level` is `disable`.
    - auto_power_level:     `enable` lets FortiOS manage transmit power between
                            `auto_power_low` and `auto_power_high`. Transmit-side
                            only — the module sends `null` unless `mode` is `ap`.
    - auto_power_low:       lower bound of the automatic transmit-power range.
    - auto_power_high:      upper bound of the automatic transmit-power range.
    - darrp:                Distributed Automatic Radio Resource Provisioning —
                            lets the controller pick the operating channel. Sent
                            only when `mode` is `ap`.
    - arrp_profile:         name of the ARRP profile tuning DARRP for this radio.
    - short_guard_interval: `enable` or `disable`. Sent only when `mode` is `ap`.
    - vap_all:              how SSIDs attach to the radio. `manual` binds only the
                            names in `vaps`; `tunnel` / `bridge` auto-bind all VAPs
                            of that forwarding type.
    - vaps:                 list of VAP (SSID) names to bind. Rendered as one
                            `vaps` block per entry; relevant when `vap_all` is
                            `manual`.
    - wids_profile:         name of the WIDS profile bound to this radio. Rejected
                            by the API when `platform.ddscan` is `enable`.
    - protection_mode:      802.11 protection for legacy-client coexistence, e.g.
                            `rtscts`, `ctsonly`, `disable`.
  EOT
  type = object({
    mode                 = optional(string, "ap")
    band                 = optional(string)
    channel              = optional(list(number), [])
    channel_bonding      = optional(string)
    power_level          = optional(number)
    auto_power_level     = optional(string, "enable")
    auto_power_low       = optional(number)
    auto_power_high      = optional(number)
    darrp                = optional(string, "enable")
    arrp_profile         = optional(string)
    short_guard_interval = optional(string, "enable")
    vap_all              = optional(string, "manual")
    vaps                 = optional(list(string), [])
    wids_profile         = optional(string)
    protection_mode      = optional(string)
  })
  default = null
}

variable "radio_2" {
  description = <<-EOT
    Configuration for the AP's second radio. Same object shape and field
    semantics as `radio_1` — see that variable for the per-field reference.
    `null` (the default) omits the `radio_2` block entirely.
  EOT
  type = object({
    mode                 = optional(string, "ap")
    band                 = optional(string)
    channel              = optional(list(number), [])
    channel_bonding      = optional(string)
    power_level          = optional(number)
    auto_power_level     = optional(string, "enable")
    auto_power_low       = optional(number)
    auto_power_high      = optional(number)
    darrp                = optional(string, "enable")
    arrp_profile         = optional(string)
    short_guard_interval = optional(string, "enable")
    vap_all              = optional(string, "manual")
    vaps                 = optional(list(string), [])
    wids_profile         = optional(string)
    protection_mode      = optional(string)
  })
  default = null
}

variable "radio_3" {
  description = <<-EOT
    Configuration for the AP's third radio, present on tri-band and quad-radio
    chassis. Same object shape and field semantics as `radio_1` — see that
    variable for the per-field reference. `null` (the default) omits the
    `radio_3` block entirely.
  EOT
  type = object({
    mode                 = optional(string, "ap")
    band                 = optional(string)
    channel              = optional(list(number), [])
    channel_bonding      = optional(string)
    power_level          = optional(number)
    auto_power_level     = optional(string, "enable")
    auto_power_low       = optional(number)
    auto_power_high      = optional(number)
    darrp                = optional(string, "enable")
    arrp_profile         = optional(string)
    short_guard_interval = optional(string, "enable")
    vap_all              = optional(string, "manual")
    vaps                 = optional(list(string), [])
    wids_profile         = optional(string)
    protection_mode      = optional(string)
  })
  default = null
}

variable "radio_4" {
  description = <<-EOT
    Configuration for the AP's fourth radio, typically the dedicated scanning or
    IoT radio on quad-radio chassis. Same object shape and field semantics as
    `radio_1` — see that variable for the per-field reference. `null` (the
    default) omits the `radio_4` block entirely.
  EOT
  type = object({
    mode                 = optional(string, "ap")
    band                 = optional(string)
    channel              = optional(list(number), [])
    channel_bonding      = optional(string)
    power_level          = optional(number)
    auto_power_level     = optional(string, "enable")
    auto_power_low       = optional(number)
    auto_power_high      = optional(number)
    darrp                = optional(string, "enable")
    arrp_profile         = optional(string)
    short_guard_interval = optional(string, "enable")
    vap_all              = optional(string, "manual")
    vaps                 = optional(list(string), [])
    wids_profile         = optional(string)
    protection_mode      = optional(string)
  })
  default = null
}
