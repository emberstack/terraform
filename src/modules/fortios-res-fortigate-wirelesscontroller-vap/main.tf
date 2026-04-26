resource "random_password" "auto" {
  count   = var.auto_generate_psk ? 1 : 0
  length  = 32
  special = false
}

locals {
  effective_passphrase   = var.passphrase != null ? var.passphrase : (var.auto_generate_psk ? random_password.auto[0].result : null)
  effective_sae_password = var.sae_password != null ? var.sae_password : (var.auto_generate_psk ? random_password.auto[0].result : null)
}

resource "fortios_wirelesscontroller_vap" "this" {
  name                      = var.name
  ssid                      = var.ssid
  security                  = var.security
  passphrase                = local.effective_passphrase
  sae_password              = local.effective_sae_password
  mpsk_profile              = var.mpsk_profile
  nac                       = var.nac
  nac_profile               = var.nac_profile
  dynamic_vlan              = var.dynamic_vlan
  vlanid                    = var.vlanid
  local_bridging            = var.local_bridging
  broadcast_ssid            = var.broadcast_ssid
  fast_bss_transition       = var.fast_bss_transition
  mbo                       = var.mbo
  pmf                       = var.pmf
  neighbor_report_dual_band = var.neighbor_report_dual_band
  sae_h2e_only              = var.sae_h2e_only
  intra_vap_privacy         = var.intra_vap_privacy
  schedule                  = var.schedule
}
