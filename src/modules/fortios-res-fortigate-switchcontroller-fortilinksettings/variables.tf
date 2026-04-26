variable "name" {
  description = "FortiLink settings name (mkey, max 35 chars). Typically matches the fortilink interface name."
  type        = string
}

variable "fortilink" {
  description = "FortiLink interface this setting applies to (e.g. \"fortilink\")."
  type        = string
}

variable "inactive_timer" {
  description = "Minutes before inactive NAC devices expire (mac age-out + inactive-time + periodic scan)."
  type        = number
  default     = 15
}

variable "link_down_flush" {
  description = "Clear NAC + dynamic devices on switch port link-down. enable | disable."
  type        = string
  default     = "enable"
}

variable "nac_ports" {
  description = "NAC port settings — controls the GUI's 'NAC VLAN segmentation' toggle via lan_segment."
  type = object({
    onboarding_vlan   = optional(string, "")
    bounce_nac_port   = optional(string, "")
    lan_segment       = optional(string, "") # enabled | disabled  (GUI: NAC VLAN segmentation)
    nac_lan_interface = optional(string, "")
    parent_key        = optional(string, "")
    member_change     = optional(number, 0)
    nac_segment_vlans = optional(list(string), [])
  })
  default = null
}
