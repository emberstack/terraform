# =============================================================================
# WINDOWS VM PRIMARY DNS SUFFIX (Microsoft.Compute/virtualMachines/extensions)
# =============================================================================
# Sets the guest primary DNS suffix via a CustomScriptExtension, then applies it
# with an ARM restart. Both are azapi: the extension is an azapi_resource and the
# restart an azapi_resource_action, so the module depends only on azapi.
#
# The restart (not an in-guest `shutdown`) is deliberate: an in-guest reboot is
# invisible to ARM, so Terraform can't wait on it; azapi blocks on the restart
# LRO until the VM is running again.
# =============================================================================

locals {
  # HKLM\...\Tcpip\Parameters - the keys the Computer Name dialog writes. The
  # restart below applies them (the value is read at boot, however triggered).
  set_dns_suffix_script = <<-PS
    $ErrorActionPreference = 'Stop'
    $suffix = '${var.dns_suffix}'
    $key    = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    Set-ItemProperty -Path $key -Name 'Domain'                   -Value $suffix -Type String
    Set-ItemProperty -Path $key -Name 'NV Domain'                -Value $suffix -Type String
    Set-ItemProperty -Path $key -Name 'SyncDomainWithMembership' -Value 0       -Type DWord
    Write-Output "Primary DNS suffix set to '$suffix'. Reboot required to take effect."
    exit 0
  PS

  # -ExecutionPolicy is omitted: it governs script files, not the inline
  # -EncodedCommand, so it would be a no-op here.
  command_to_execute = "powershell.exe -NoProfile -EncodedCommand ${textencodebase64(local.set_dns_suffix_script, "UTF-16LE")}"
}

resource "azapi_resource" "dns_suffix" {
  type      = "Microsoft.Compute/virtualMachines/extensions@2024-07-01"
  name      = "SetPrimaryDnsSuffix"
  parent_id = var.virtual_machine_id
  location  = var.location
  tags      = var.tags

  # settings is a native object - azapi serializes the whole body to JSON, so no
  # jsonencode() wrapper is needed around it.
  body = {
    properties = {
      publisher                = "Microsoft.Compute"
      type                     = "CustomScriptExtension"
      typeHandlerVersion       = "1.10"
      autoUpgradeMinorVersion  = true
      provisionAfterExtensions = var.provision_after_extensions
      settings = {
        commandToExecute = local.command_to_execute
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Apply the suffix with an ARM restart (blocks until the VM is running again)
# -----------------------------------------------------------------------------
# replace_triggered_by keys on the extension's body, which carries the settings
# (and thus the suffix). It changes iff the script/suffix changes; tags are a
# separate top-level attribute, not part of body, so they don't re-fire it.

resource "azapi_resource_action" "reboot" {
  count = var.reboot ? 1 : 0

  type        = "Microsoft.Compute/virtualMachines@2024-07-01"
  resource_id = var.virtual_machine_id
  action      = "restart"
  method      = "POST"

  timeouts {
    create = "15m"
  }

  lifecycle {
    replace_triggered_by = [azapi_resource.dns_suffix.body]
  }

  depends_on = [azapi_resource.dns_suffix]
}
