variable "name" {
  description = "Name of the wireless NAC profile. This is the FortiOS mkey — changing it replaces the object. Referenced by name from a VAP's `nac_profile`."
  type        = string
}

variable "comment" {
  description = "Free-text comment stored on the NAC profile object. Cosmetic only."
  type        = string
  default     = ""
}

variable "onboarding_vlan" {
  description = "VLAN interface name to assign onboarding clients."
  type        = string
}
