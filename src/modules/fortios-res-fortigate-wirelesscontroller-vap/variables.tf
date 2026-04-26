variable "name" {
  description = "Name of the VAP (virtual AP) object. This is the FortiOS mkey and the interface name the VAP appears as on the FortiGate — changing it replaces the object."
  type        = string
}

variable "ssid" {
  description = "SSID broadcast by this VAP. Independent of `name`; the two do not have to match."
  type        = string
}

variable "security" {
  description = "Wireless security mode for the VAP, e.g. `open`, `owe`, `wpa2-only-personal`, `wpa3-sae`, `wpa3-sae-transition`, `wpa2-only-enterprise`, `wpa3-enterprise`. Determines which credential field is honoured: personal/transition modes use `passphrase`, SAE modes use `sae_password`. Default `wpa3-sae-transition` runs WPA2-PSK and WPA3-SAE side by side."
  type        = string
  default     = "wpa3-sae-transition"
}

variable "passphrase" {
  description = "WPA2 pre-shared key. Applies to the personal/transition security modes. When left `null` and `auto_generate_psk` is true, the module substitutes an internally generated 32-character value."
  type        = string
  default     = null
  sensitive   = true
}

variable "sae_password" {
  description = "WPA3 SAE password. Applies to the SAE/transition security modes. When left `null` and `auto_generate_psk` is true, the module substitutes the same internally generated 32-character value used for `passphrase`."
  type        = string
  default     = null
  sensitive   = true
}

variable "mpsk_profile" {
  description = "Name of an existing `wireless-controller.mpsk-profile` to attach, giving the VAP multiple per-client pre-shared keys instead of one shared passphrase. `null` leaves the VAP on a single PSK."
  type        = string
  default     = null
}

variable "nac" {
  description = "Enable network access control (device onboarding/quarantine) on this VAP. One of `enable` or `disable`. Pair with `nac_profile`."
  type        = string
  default     = "disable"
}

variable "nac_profile" {
  description = "Name of the `wireless-controller.nac-profile` applied to matched devices. Only meaningful when `nac` is `enable`."
  type        = string
  default     = null
}

variable "dynamic_vlan" {
  description = "Enable RADIUS-assigned (per-user) VLAN placement for clients on this VAP. One of `enable` or `disable`. When `disable`, all clients land on `vlanid`."
  type        = string
  default     = "disable"
}

variable "vlanid" {
  description = "Static VLAN ID tagged on traffic from this VAP. `0` means no VLAN tag — traffic stays on the VAP's own interface."
  type        = number
  default     = 0
}

variable "local_bridging" {
  description = "Bridge client traffic locally at the FortiAP onto its wired LAN instead of tunnelling it back to the FortiGate (CAPWAP). One of `enable` or `disable`. Locally bridged traffic bypasses FortiGate policy inspection."
  type        = string
  default     = "enable"
}

variable "broadcast_ssid" {
  description = "Include the SSID in beacon frames. One of `enable` or `disable`. `disable` makes the network hidden (clients must know the SSID)."
  type        = string
  default     = "enable"
}

variable "fast_bss_transition" {
  description = "Enable 802.11r fast BSS transition so clients roam between APs without a full re-auth. One of `enable` or `disable`. Some older clients mis-handle 802.11r."
  type        = string
  default     = "enable"
}

variable "mbo" {
  description = "Enable Multiband Operation (Wi-Fi Agile Multiband), letting the controller steer capable clients between bands/APs. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "pmf" {
  description = "802.11w Protected Management Frames mode. One of `disable`, `enable` or `optional`. WPA3/SAE requires PMF, so `optional` is the workable setting for a WPA2/WPA3 transition SSID; `enable` locks out clients that cannot do PMF."
  type        = string
  default     = "optional"
}

variable "neighbor_report_dual_band" {
  description = "Include cross-band (2.4↔5) BSSs in 802.11k neighbor reports. Enable to help sticky 2.4 GHz clients band-steer to 5 GHz when roaming. Note: 80211k and 80211v themselves are FortiOS-default enable, so they're not separate vars."
  type        = string
  default     = null
}

variable "sae_h2e_only" {
  description = "Accept only SAE Hash-to-Element authentication, rejecting the legacy hunting-and-pecking exchange. One of `enable` or `disable`. Older WPA3 clients may fail to associate when `enable`."
  type        = string
  default     = "disable"
}

variable "intra_vap_privacy" {
  description = "Client isolation: block station-to-station traffic between clients associated to this VAP. One of `enable` or `disable`."
  type        = string
  default     = "disable"
}

variable "schedule" {
  description = "Name of the firewall schedule that controls when this VAP is broadcast. `always` is the factory schedule and keeps the SSID up permanently."
  type        = string
  default     = "always"
}

variable "auto_generate_psk" {
  description = "If true, generate a random 32-char alphanumeric PSK internally. Use only for never-broadcast dummy VAPs (e.g. AP LAN port bridges)."
  type        = bool
  default     = false
}
