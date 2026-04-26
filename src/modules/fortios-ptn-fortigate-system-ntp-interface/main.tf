# =============================================================================
# FORTIGATE NTP LISTENER INTERFACE
# =============================================================================
# The fortios provider exposes `system/ntp` as a whole-object resource with no
# way to add a single listener interface without owning the entire NTP config,
# so this module drives the CMDB REST endpoint directly via local-exec.
#
# Ownership tracking: the data source is read first, and `owned` records whether
# this module created the listener. A pre-existing listener is left alone on
# destroy — we only remove what we added.
#
# Runtime contract (NOT declared as Terraform inputs — the provisioners read
# them from the environment at apply time):
#   - `pwsh` (PowerShell 7+) must be on PATH; -SkipCertificateCheck and
#     Invoke-RestMethod splatting are not available in Windows PowerShell 5.1.
#   - FORTIOS_ACCESS_HOSTNAME — FortiGate host, no scheme.
#   - FORTIOS_ACCESS_TOKEN    — REST API token.
# These mirror the environment the fortios provider itself is configured from.
# =============================================================================

data "fortios_system_ntp" "current" {}

locals {
  current_interfaces = [for i in try(data.fortios_system_ntp.current.interface, []) : i.interface_name]
  already_exists     = contains(local.current_interfaces, var.interface_name)
}

resource "terraform_data" "ntp_interface" {
  input = {
    interface_name = var.interface_name
    owned          = !local.already_exists
    insecure       = var.insecure
  }

  lifecycle {
    ignore_changes = [input]
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-NoProfile", "-Command"]
    command     = <<-EOT
      if ("${self.input.owned}" -eq "true") {
        $params = @{
          Uri         = "https://$env:FORTIOS_ACCESS_HOSTNAME/api/v2/cmdb/system/ntp/interface"
          Method      = 'POST'
          Headers     = @{ Authorization = "Bearer $env:FORTIOS_ACCESS_TOKEN" }
          Body        = '${jsonencode({ "interface-name" = var.interface_name })}'
          ContentType = 'application/json'
        }
        if ("${var.insecure}" -eq "true") { $params['SkipCertificateCheck'] = $true }
        Invoke-RestMethod @params | Out-Null
        Write-Host "Added NTP listener: ${var.interface_name}"
      } else {
        Write-Host "NTP listener already exists: ${var.interface_name}"
      }
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["pwsh", "-NoProfile", "-Command"]
    command     = <<-EOT
      if ("${self.input.owned}" -eq "true") {
        $params = @{
          Uri     = "https://$env:FORTIOS_ACCESS_HOSTNAME/api/v2/cmdb/system/ntp/interface/${self.input.interface_name}"
          Method  = 'DELETE'
          Headers = @{ Authorization = "Bearer $env:FORTIOS_ACCESS_TOKEN" }
        }
        if ("${try(self.input.insecure, true)}" -eq "true") { $params['SkipCertificateCheck'] = $true }
        try {
          Invoke-RestMethod @params | Out-Null
          Write-Host "Removed NTP listener: ${self.input.interface_name}"
        } catch {
          if ($_.Exception.Response.StatusCode.value__ -eq 404) {
            Write-Host "NTP listener already gone: ${self.input.interface_name}"
          } else { throw }
        }
      } else {
        Write-Host "NTP listener was pre-existing — skipping cleanup: ${self.input.interface_name}"
      }
    EOT
  }
}
