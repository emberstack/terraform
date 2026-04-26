variable "wtp_id" {
  description = "AP serial number (e.g. FP441KTF12345678)"
  type        = string
}

variable "name" {
  description = "Friendly name for the AP, shown in the managed-AP list in place of the serial. Left `null` by default so FortiOS keeps displaying the serial."
  type        = string
  default     = null
}

variable "admin" {
  description = "Administrative state of the AP entry on the controller. One of `discovered`, `disable` or `enable`; `enable` authorizes the AP so it is allowed to join and be managed."
  type        = string
  default     = "enable"
}

variable "wtp_profile" {
  description = "Name of the wtp-profile (AP profile) this AP is bound to — the profile supplies the radio, LAN and management settings. Usually wired from the `name` output of the `fortios-res-fortigate-wirelesscontroller-wtpprofile` module."
  type        = string
}

variable "location" {
  description = "Free-text location label stored on the AP entry and shown in the managed-AP list. Descriptive only; no effect on AP behavior."
  type        = string
  default     = ""
}

variable "override_allowaccess" {
  description = "Whether this AP overrides the management-access list inherited from its wtp-profile. One of `enable` or `disable`. Must be `enable` for `allowaccess` to be sent at all — the module passes `null` otherwise."
  type        = string
  default     = "disable"
}

variable "allowaccess" {
  description = "Space-separated list of management protocols permitted on the AP itself, e.g. `https ssh snmp`. Only applied when `override_allowaccess` is `enable`; otherwise it is ignored and the AP inherits the profile's list."
  type        = string
  default     = "https ssh snmp"
}

variable "ip_fragment_preventing" {
  description = "Anti-fragmentation strategy for CAPWAP control. 'tcp-mss-adjust' (FortiOS default) clamps TCP MSS so fragmentation never happens. Matches box-default on F-series and K-series chassis."
  type        = string
  default     = "tcp-mss-adjust"
}

variable "mesh_bridge_enable" {
  description = "When 'enable', this AP can act as a mesh bridge root or relay. 'default' inherits chassis-vendor default; 'disable' for non-mesh deployments."
  type        = string
  default     = "default"
}
