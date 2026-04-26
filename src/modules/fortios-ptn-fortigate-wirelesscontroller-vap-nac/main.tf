locals {
  nac_profile_name = coalesce(var.nac_profile_name, var.name)
}

# -----------------------------------------------------------------------------
# Step 1 — VAP (base, no NAC). Field-ownership of nac/nac-profile is delegated
# to the terraform_data binding below, so ignore drift on those two fields.
# -----------------------------------------------------------------------------

resource "fortios_wirelesscontroller_vap" "this" {
  name                      = var.name
  ssid                      = var.ssid
  security                  = var.security
  passphrase                = var.passphrase
  sae_password              = var.sae_password
  mpsk_profile              = var.mpsk_profile
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

  lifecycle {
    ignore_changes = [nac, nac_profile]
  }
}

# -----------------------------------------------------------------------------
# Step 2 — VAP sub-interfaces (one per NAC steering target + the onboarding).
# parent_interface = the VAP itself, so Terraform serializes after step 1.
# -----------------------------------------------------------------------------

resource "fortios_system_interface" "nac_vlans" {
  for_each = var.nac_vlans

  vdom            = "root"
  update_if_exist = true

  name      = each.value.name
  alias     = each.value.alias
  type      = "vlan"
  role      = each.value.role
  interface = fortios_wirelesscontroller_vap.this.name
  vlanid    = each.value.vlanid
  ip        = "0.0.0.0 0.0.0.0"
}

# -----------------------------------------------------------------------------
# Step 3 — NAC profile. onboarding-vlan must be a VAP sub-interface (fortilink-
# side VLANs are rejected with -3), hence the indirection via nac_vlans[key].
# -----------------------------------------------------------------------------

resource "fortios_wirelesscontroller_nacprofile" "this" {
  name            = local.nac_profile_name
  comment         = var.nac_profile_comment
  onboarding_vlan = fortios_system_interface.nac_vlans[var.onboarding_vlan_key].name
}

# -----------------------------------------------------------------------------
# Step 4 — bind NAC onto the VAP via REST PUT. Runs last (depends on step 3).
# -----------------------------------------------------------------------------

resource "terraform_data" "nac_binding" {
  # terraform_data auto-replaces whenever `input` changes, which re-fires the
  # create-time provisioner. No explicit replace_triggered_by needed.
  input = {
    vap_name    = fortios_wirelesscontroller_vap.this.name
    nac_profile = fortios_wirelesscontroller_nacprofile.this.name
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-NoProfile", "-Command"]
    command     = <<-EOT
      $body = @{ nac = 'enable'; 'nac-profile' = '${self.input.nac_profile}' } | ConvertTo-Json
      Invoke-RestMethod `
        -Uri "https://$env:FORTIOS_ACCESS_HOSTNAME/api/v2/cmdb/wireless-controller/vap/${self.input.vap_name}" `
        -Method PUT `
        -Headers @{ Authorization = "Bearer $env:FORTIOS_ACCESS_TOKEN" } `
        -Body $body `
        -ContentType "application/json" `
        -SkipCertificateCheck | Out-Null
      Write-Host "Bound NAC profile '${self.input.nac_profile}' on VAP '${self.input.vap_name}'"
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["pwsh", "-NoProfile", "-Command"]
    command     = <<-EOT
      $body = @{ nac = 'disable'; 'nac-profile' = '' } | ConvertTo-Json
      try {
        Invoke-RestMethod `
          -Uri "https://$env:FORTIOS_ACCESS_HOSTNAME/api/v2/cmdb/wireless-controller/vap/${self.input.vap_name}" `
          -Method PUT `
          -Headers @{ Authorization = "Bearer $env:FORTIOS_ACCESS_TOKEN" } `
          -Body $body `
          -ContentType "application/json" `
          -SkipCertificateCheck | Out-Null
        Write-Host "Cleared NAC binding on VAP '${self.input.vap_name}'"
      } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 404) {
          Write-Host "VAP '${self.input.vap_name}' already gone — skipping unbind"
        } else { throw }
      }
    EOT
  }
}
