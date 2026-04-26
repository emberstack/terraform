# =============================================================================
# Standard interface pattern — composes one interface with its optional
# satellite resources (addresses, DHCP server, DNS server, NTP listener).
# Replaces the per-leaf split under interfaces/<vlan>/{interface,addresses,
# dhcp-server,dns-server,ntp-server}/ with a single leaf.
# =============================================================================

# -----------------------------------------------------------------------------
# Interface — always created. Fields mirror fortios-res-fortigate-system-interface.
# -----------------------------------------------------------------------------

variable "name" {
  description = "Interface name as it appears in the FortiGate config (e.g. `port1`, `vlan100`). Immutable — changing it replaces the interface and every satellite resource attached to it."
  type        = string
}

variable "alias" {
  description = "Human-friendly label shown next to the interface name in the GUI. Empty string leaves it unset. Also feeds the `display_name` output."
  type        = string
  default     = ""
}

variable "description" {
  description = "Free-text description stored on the interface."
  type        = string
  default     = ""
}

variable "type" {
  description = "Interface type. `physical` for a real port, `vlan` for a tagged sub-interface (requires `vlanid` and `parent_interface`), `aggregate` for a LAG (requires `members`), `loopback`, `tunnel`, `hard-switch`, etc."
  type        = string
  default     = "physical"
}

variable "role" {
  description = "Interface role, which drives which fields the GUI exposes. One of `lan`, `wan`, `dmz` or `undefined`."
  type        = string
  default     = "lan"
}

variable "mode" {
  description = "IPv4 addressing mode. `static` uses the `ip`/`netmask` pair; `dhcp` or `pppoe` obtain the address from upstream and make `ip` irrelevant."
  type        = string
  default     = "static"
}

variable "ip" {
  description = "IPv4 address of the interface, without a prefix (e.g. `10.0.10.1`). Combined with `netmask` into the single space-separated `ip` value FortiOS expects. Leave `null` to send no address — required when `mode` is not `static`."
  type        = string
  default     = null
}

variable "netmask" {
  description = "Dotted-decimal subnet mask paired with `ip` (e.g. `255.255.255.0`). Only sent when `ip` is non-null."
  type        = string
  default     = "255.255.255.0"
}

variable "allowaccess" {
  description = "Space-separated list of management services permitted on this interface, e.g. `\"ping https ssh snmp fgfm\"`. Empty string allows nothing."
  type        = string
  default     = ""
}

variable "color" {
  description = "GUI colour index (0 = default palette entry). Deliberately only sent when `parent_interface` is set — on non-VLAN interfaces FortiOS rewrites the value and the field would diff forever."
  type        = number
  default     = 0
}

variable "dns_server_override" {
  description = "Whether DNS servers learned on this interface (DHCP/PPPoE) may override the system DNS. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "device_identification" {
  description = "Enable device detection/fingerprinting of hosts on this interface. One of `enable` or `disable`."
  type        = string
  default     = "disable"
}

variable "vlanid" {
  description = "802.1Q VLAN tag. Only meaningful when `type` is `vlan`; leave `null` otherwise."
  type        = number
  default     = null
}

variable "parent_interface" {
  description = "Underlying interface this one is built on — the trunk port for a `vlan`, or the FortiLink interface for a switch-controller VLAN. Maps to the FortiOS `interface` field. Also gates whether `color` is sent."
  type        = string
  default     = null
}

variable "members" {
  description = "Member interface names bundled into an `aggregate` or `hard-switch` interface. Renders one `member` block per entry; empty list emits none."
  type        = list(string)
  default     = []
}

variable "lacp_mode" {
  description = "LACP behaviour on an `aggregate` interface. One of `static`, `passive` or `active`. Leave `null` on non-aggregate interfaces."
  type        = string
  default     = null
}

variable "fortilink_split_interface" {
  description = "On a FortiLink aggregate, whether the members are split across two switches (MCLAG). One of `enable` or `disable`."
  type        = string
  default     = null
}

variable "swc_first_create" {
  description = "Switch-controller bookkeeping counter FortiOS stamps on VLANs it auto-creates. Set it explicitly to match the device value when adopting an auto-created interface, otherwise leave `null`."
  type        = number
  default     = null
}

variable "switch_controller_dynamic" {
  description = "Name of the switch-controller dynamic port policy bound to this VLAN. Leave `null` when unused."
  type        = string
  default     = null
}

variable "switch_controller_nac" {
  description = "Name of the switch-controller NAC policy applied to this VLAN. Leave `null` when unused."
  type        = string
  default     = null
}

variable "switch_controller_access_vlan" {
  description = "GUI label: 'Block intra-VLAN traffic'. enable = blocked, disable = clients can L2-talk."
  type        = string
  default     = null
}

variable "switch_controller_feature" {
  description = "NAC segment feature flag: nac | nac-segment | none. Set explicitly to avoid drift on FortiLink-auto-created VLANs."
  type        = string
  default     = null
}

variable "security_mode" {
  description = "captive-portal | none | etc. Optional, only set when you want captive portal."
  type        = string
  default     = null
}

variable "auto_auth_extension_device" {
  description = "Automatically authorise FortiExtender devices discovered on this interface. One of `enable` or `disable`."
  type        = string
  default     = "disable"
}

variable "ike_saml_server" {
  description = "Name of the SAML server used for IKE SAML authentication on this interface. Empty string leaves it unset."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Satellite resources — each is created only when its variable is non-null.
# -----------------------------------------------------------------------------

# display_with defaults to icon-and-color so `color` actually renders; FortiOS
# 8.0+ can show custom_tags badges instead.
variable "addresses" {
  description = "Optional firewall address objects associated with this interface. Empty map skips creation."
  type = map(object({
    name          = string
    type          = optional(string, "ipmask")
    subnet        = optional(string)
    start_ip      = optional(string)
    end_ip        = optional(string)
    fqdn          = optional(string)
    country       = optional(string)
    interface     = optional(string)
    color         = optional(number, 0)
    display_with  = optional(string, "icon-and-color")
    custom_tags   = optional(list(string), [])
    allow_routing = optional(string, "disable")
    comment       = optional(string)
  }))
  default = {}
}

# display_with is deliberately NOT defaulted here: FortiOS honours it on
# addresses but reverts groups to all-tags, so a default would diff forever.
variable "address_groups" {
  description = "Optional firewall address groups (members reference addresses by name). Empty map skips creation."
  type = map(object({
    name          = string
    member        = list(string)
    color         = optional(number, 0)
    display_with  = optional(string)
    custom_tags   = optional(list(string), [])
    allow_routing = optional(string, "disable")
    comment       = optional(string)
  }))
  default = {}
}

variable "dhcp_server" {
  description = "Optional DHCP server for this interface. Set to null to skip."
  type = object({
    default_gateway = string
    netmask         = optional(string, "255.255.255.0")
    dns_service     = optional(string, "local")
    ntp_service     = optional(string, "local")
    lease_time      = optional(number, 604800)
    status          = optional(string, "enable")
    ip_ranges = list(object({
      id       = number
      start_ip = string
      end_ip   = string
    }))
    vci_strings = optional(list(string), [])
    reserved_addresses = optional(list(object({
      id          = number
      ip          = string
      mac         = string
      description = optional(string, "")
    })), [])
  })
  default = null
}

variable "dns_server" {
  description = "Optional DNS server on this interface. Set to null to skip."
  type = object({
    mode              = optional(string, "recursive")
    dnsfilter_profile = optional(string, "")
  })
  default = null
}

variable "ntp_listener" {
  description = "Enable this interface as an NTP listener so LAN clients can sync against the FortiGate."
  type        = bool
  default     = false
}
