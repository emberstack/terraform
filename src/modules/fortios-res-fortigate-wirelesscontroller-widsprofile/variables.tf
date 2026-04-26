variable "name" {
  description = "Name of the WIDS profile. This is the FortiOS mkey and the value a wtp-profile radio references via its `wids_profile` field."
  type        = string
}

variable "comment" {
  description = "Free-text comment stored on the profile."
  type        = string
  default     = ""
}

variable "sensor_mode" {
  description = "Wireless intrusion sensor mode used to detect foreign (rogue) APs. One of `disable`, `foreign` (scan other-network APs only) or `both` (scan foreign and own-network APs)."
  type        = string
  default     = "disable"
}

variable "ap_scan" {
  description = "Rogue AP detection scanning on radios bound to this profile. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "ap_scan_passive" {
  description = "Passive scanning — the radio listens only and does not transmit probe requests while scanning. One of `enable` or `disable`."
  type        = string
  default     = "disable"
}

variable "wireless_bridge" {
  description = "Detection of wireless bridge frames. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "deauth_broadcast" {
  description = "Detection of broadcast deauthentication attacks. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "deauth_unknown_src_thresh" {
  description = "Threshold for deauthentication frames received from an unknown source before the event is flagged, in frames. `0` disables the check."
  type        = number
  default     = 10
}

variable "assoc_flood_thresh" {
  description = "Number of association requests within `assoc_flood_time` that trips association flood detection. Only meaningful when `assoc_frame_flood` is `enable`."
  type        = number
  default     = 30
}

variable "assoc_flood_time" {
  description = "Window, in seconds, over which `assoc_flood_thresh` association requests are counted. Only meaningful when `assoc_frame_flood` is `enable`."
  type        = number
  default     = 10
}

variable "assoc_frame_flood" {
  description = "Detection of association request flooding, using `assoc_flood_thresh` over `assoc_flood_time`. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "auth_flood_thresh" {
  description = "Number of authentication requests within `auth_flood_time` that trips authentication flood detection. Only meaningful when `auth_frame_flood` is `enable`."
  type        = number
  default     = 30
}

variable "auth_flood_time" {
  description = "Window, in seconds, over which `auth_flood_thresh` authentication requests are counted. Only meaningful when `auth_frame_flood` is `enable`."
  type        = number
  default     = 10
}

variable "auth_frame_flood" {
  description = "Detection of authentication request flooding, using `auth_flood_thresh` over `auth_flood_time`. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "weak_wep_iv" {
  description = "Detection of WEP initialization vectors known to be weak. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "spoofed_deauth" {
  description = "Detection of spoofed deauthentication frames. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "eapol_logoff_flood" {
  description = "Detection of EAPOL-Logoff frame flooding. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "eapol_pre_succ_flood" {
  description = "Detection of premature EAPOL-Success frame flooding — EAPOL-Success frames sent to a station before authentication has actually completed. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "eapol_pre_fail_flood" {
  description = "Detection of premature EAPOL-Failure frame flooding — EAPOL-Failure frames sent to a station before authentication has actually completed. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}
