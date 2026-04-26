# =============================================================================
# Pattern: wireless VAP with NAC steering
# =============================================================================
# One leaf, one Terraform run = full wireless-NAC stack:
#
#   1. wireless-controller/vap                  (nac=disable initially)
#   2. system/interface  (×N)                    VAP sub-interfaces, parent=VAP
#   3. wireless-controller/nac-profile           onboarding-vlan = one sub-int
#   4. wireless-controller/vap (PUT)             nac=enable, nac-profile=<name>
#
# The four-step Fortinet bootstrap (per FortiAP 7.6 config guide
# §"Configuring wireless NAC support") is collapsed into a single graph here.
# All four steps share intra-module resource refs, so Terraform serializes
# them in the right order automatically — no cycle, no manual choreography,
# no two-pass apply.
#
# Step 4 is a `terraform_data` REST PUT rather than a second native VAP
# resource because two managed resources pointing at the same mkey would
# fight over field ownership. terraform_data lets us flip JUST nac/nac-profile
# without touching the rest of the VAP — and `lifecycle.ignore_changes` on
# the VAP resource keeps it from clawing them back on the next refresh.
# =============================================================================

# -----------------------------------------------------------------------------
# VAP — all the standard fields, pass-through to fortios_wirelesscontroller_vap.
# -----------------------------------------------------------------------------

variable "name" {
  description = "VAP interface name (e.g. nac-ssid). Becomes the FortiOS mkey."
  type        = string
}

variable "ssid" {
  description = "Broadcast SSID (e.g. corp-nac)."
  type        = string
}

variable "security" {
  description = "Security mode for the VAP (e.g. `wpa3-sae-transition`, `wpa2-only-personal`, `wpa3-sae`, `open`). Determines which of `passphrase` / `sae_password` / `mpsk_profile` is actually used."
  type        = string
  default     = "wpa3-sae-transition"
}

variable "passphrase" {
  description = "WPA2 pre-shared key. Only meaningful for WPA2-personal security modes (including the WPA2 half of `wpa3-sae-transition`)."
  type        = string
  default     = null
  sensitive   = true
}

variable "sae_password" {
  description = "WPA3 SAE password. Only meaningful when `security` selects an SAE mode (`wpa3-sae`, `wpa3-sae-transition`)."
  type        = string
  default     = null
  sensitive   = true
}

variable "mpsk_profile" {
  description = "Name of an existing wireless-controller multi-PSK profile to attach to the VAP. Leave `null` when using a single passphrase."
  type        = string
  default     = null
}

variable "vlanid" {
  description = "Default VLAN on the bare VAP (typically 0; per-device VLANs are assigned by NAC)."
  type        = number
  default     = 0
}

variable "local_bridging" {
  description = "Bridge client traffic locally at the FortiAP instead of tunnelling it to the FortiGate. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "broadcast_ssid" {
  description = "Advertise the SSID in beacons. `disable` makes it a hidden network. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "fast_bss_transition" {
  description = "802.11r fast BSS transition (fast roaming between APs). One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "mbo" {
  description = "802.11v/Wi-Fi Agile Multiband (MBO) support, used for AP-assisted client steering. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "pmf" {
  description = "802.11w protected management frames. One of `disable`, `enable` (required) or `optional`. Note that SAE/WPA3 modes require PMF, so `disable` will be rejected there."
  type        = string
  default     = "optional"
}

variable "neighbor_report_dual_band" {
  description = "Include cross-band (2.4↔5) BSSs in 802.11k neighbor reports. Helps sticky clients band-steer on roam."
  type        = string
  default     = null
}

variable "sae_h2e_only" {
  description = "Accept only SAE hash-to-element, rejecting the legacy hunting-and-pecking handshake. One of `enable` or `disable`. Older WPA3 clients may fail to associate when enabled."
  type        = string
  default     = "disable"
}

variable "intra_vap_privacy" {
  description = "Client isolation — block station-to-station traffic within the VAP. One of `enable` or `disable`."
  type        = string
  default     = "disable"
}

variable "schedule" {
  description = "Name of the firewall schedule controlling when the SSID is available. `always` keeps it up permanently."
  type        = string
  default     = "always"
}

# -----------------------------------------------------------------------------
# NAC stack — VAP sub-interfaces + profile + binding.
# -----------------------------------------------------------------------------

variable "nac_vlans" {
  description = <<-EOT
    Map of VAP sub-interfaces (steering targets + onboarding). Key is a local
    handle used downstream (e.g. by onboarding_vlan_key, or by leaves looking
    up a specific steering target). Each value declares the FortiOS interface
    name and alias explicitly. Each sub-interface is created parent = this
    VAP and no L3 (the matching fortilink-side VLAN owns DHCP/routing).
  EOT
  type = map(object({
    name   = string
    alias  = optional(string, "")
    vlanid = number
    role   = optional(string, "lan")
  }))
}

variable "onboarding_vlan_key" {
  description = "Key in nac_vlans that the nac-profile uses as its onboarding-vlan."
  type        = string
}

variable "nac_profile_name" {
  description = "Name for the wireless-controller/nac-profile. Defaults to var.name."
  type        = string
  default     = null
}

variable "nac_profile_comment" {
  description = "Free-text comment stored on the wireless-controller/nac-profile."
  type        = string
  default     = ""
}
