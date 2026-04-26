# -----------------------------------------------------------------------------
# VAP
# -----------------------------------------------------------------------------

output "vap_id" {
  description = "Terraform resource ID of the VAP. For this provider it is the FortiOS mkey, i.e. the same value as `vap_name`."
  value       = fortios_wirelesscontroller_vap.this.id
}

output "vap_name" {
  description = "Name of the created VAP interface. Use this to reference the SSID from AP profiles, SSID policies or firewall policies."
  value       = fortios_wirelesscontroller_vap.this.name
}

output "ssid" {
  description = "Broadcast SSID configured on the VAP."
  value       = fortios_wirelesscontroller_vap.this.ssid
}

# -----------------------------------------------------------------------------
# NAC sub-interfaces — keyed map of {name, vlanid, alias} for downstream
# consumers (e.g. ssid-policies referencing a specific steering target).
# -----------------------------------------------------------------------------

output "nac_vlans" {
  description = "Created VAP sub-interfaces, keyed by the same key used in `var.nac_vlans`. Each value is `{ name, alias, vlanid }` — the interface name is what downstream NAC policies and firewall policies reference as a steering target."
  value = {
    for k, v in fortios_system_interface.nac_vlans : k => {
      name   = v.name
      alias  = v.alias
      vlanid = v.vlanid
    }
  }
}

# -----------------------------------------------------------------------------
# NAC profile
# -----------------------------------------------------------------------------

output "nac_profile_name" {
  description = "Name of the wireless-controller/nac-profile bound to the VAP. Reference it from NAC policies that steer devices onto this SSID."
  value       = fortios_wirelesscontroller_nacprofile.this.name
}

output "onboarding_vlan_name" {
  description = "Interface name of the VAP sub-interface used as the profile's onboarding VLAN — the entry in `nac_vlans` selected by `onboarding_vlan_key`."
  value       = fortios_system_interface.nac_vlans[var.onboarding_vlan_key].name
}
