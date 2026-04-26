variable "update_if_exist" {
  description = "If true, an existing interface with the same name is updated in place instead of erroring on duplicate-mkey."
  type        = bool
  default     = true
  nullable    = false
}

variable "vdom" {
  description = "VDOM the interface belongs to. Defaults to `root`, which is the only VDOM on a device that has not had VDOMs enabled."
  type        = string
  default     = "root"
  nullable    = false
}

variable "name" {
  description = "Interface name (for example `port1`, `vlan100`, `agg1`). This is the resource mkey and is also what the `data.fortios_system_interface` read-back lookup keys on."
  type        = string
}

variable "alias" {
  description = "Friendly label shown next to the interface name in the GUI. Empty string clears it. Also feeds the `display_name` output, which falls back to `name` when this is empty."
  type        = string
  default     = ""
}

variable "description" {
  description = "Free-text description stored on the interface."
  type        = string
  default     = ""
}

variable "type" {
  description = "Interface type. Common values are `physical`, `vlan`, `aggregate`, `loopback`, `tunnel` and `switch`. `vlan` additionally requires `vlanid` and `parent_interface`; `aggregate` pairs with `members` and `lacp_mode`."
  type        = string
  default     = "physical"
}

variable "role" {
  description = "Interface role, which drives which GUI fields and defaults FortiOS offers. One of `lan`, `wan`, `dmz` or `undefined`."
  type        = string
  default     = "lan"
}

variable "mode" {
  description = "How the interface obtains its IPv4 address. One of `static`, `dhcp` or `pppoe`. `ip`/`netmask` only apply when this is `static`."
  type        = string
  default     = "static"
}

variable "ip" {
  description = "IPv4 address of the interface, without a prefix (for example `10.0.10.1`). The module joins this with `netmask` into the single `ip` field FortiOS expects. Leave `null` to send no address at all — `netmask` alone has no effect."
  type        = string
  default     = null
}

variable "netmask" {
  description = "Dotted-quad subnet mask paired with `ip` (for example `255.255.255.0`). Ignored unless `ip` is set."
  type        = string
  default     = "255.255.255.0"
}

variable "allowaccess" {
  description = "Space-separated list of management protocols permitted on the interface, for example `\"ping https ssh\"`. Empty string permits none. This attribute is a full replacement — list every protocol you want kept."
  type        = string
  default     = ""
}

variable "color" {
  description = <<-EOT
    GUI colour index for the interface.

    ⚠️ Only applied when `parent_interface` is set (i.e. to VLAN sub-interfaces).
    For a physical or aggregate interface this value is **silently discarded** —
    see the `color` line in main.tf. Sending it unconditionally would rewrite the
    colour of every existing interface this module manages, so the restriction is
    left in place deliberately.
  EOT
  type        = number
  default     = 0
  nullable    = false
}

variable "dns_server_override" {
  description = "Whether DNS servers learned on this interface (via DHCP or PPPoE) may override the system DNS settings. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "device_identification" {
  description = "Whether the FortiGate performs device detection/fingerprinting on hosts seen through this interface. One of `enable` or `disable`."
  type        = string
  default     = "disable"
}

variable "vlanid" {
  description = "802.1Q VLAN tag carried on the sub-interface. Only meaningful when `type` is `vlan`, in which case `parent_interface` must also be set. Leave `null` for non-VLAN interfaces."
  type        = number
  default     = null
}

variable "parent_interface" {
  description = "Name of the physical or aggregate interface this VLAN sub-interface rides on; maps to the FortiOS `interface` field. Also acts as the gate for `color` — that value is only sent when this is non-null."
  type        = string
  default     = null
}

variable "members" {
  description = "Member interface names bundled into this interface, used for `aggregate` (and switch) types. Each entry becomes one `member` block via a `dynamic` block; the default empty list emits no member blocks at all, leaving any existing membership untouched by this attribute."
  type        = list(string)
  default     = []
}

variable "lacp_mode" {
  description = "LACP behaviour for an `aggregate` interface. One of `static`, `passive` or `active`. Leave `null` for non-aggregate interfaces so the field is not sent."
  type        = string
  default     = null
}

variable "fortilink_split_interface" {
  description = "Whether a FortiLink aggregate is split across two switches in a stack/MCLAG pair. One of `enable` or `disable`. Leave `null` to omit the field."
  type        = string
  default     = null
}

variable "swc_first_create" {
  description = "Maps to the FortiOS `swc-first-create` field on switch-controller-managed interfaces. Leave `null` unless you need to pin the value the FortiGate wrote to stop it drifting."
  type        = number
  default     = null
}

variable "switch_controller_dynamic" {
  description = "Name of the switch-controller dynamic-VLAN mapping applied to this interface. Leave `null` to omit the field."
  type        = string
  default     = null
}

variable "switch_controller_nac" {
  description = "Name of the switch-controller NAC policy/segment this interface belongs to. Leave `null` to omit the field."
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
  description = "Whether FortiExtender devices discovered on this interface are authorised automatically. One of `enable` or `disable`."
  type        = string
  default     = "disable"
}

variable "ike_saml_server" {
  description = "Name of the SAML server used for IKE (dial-up IPsec) authentication on this interface. Empty string means none."
  type        = string
  default     = ""
}
