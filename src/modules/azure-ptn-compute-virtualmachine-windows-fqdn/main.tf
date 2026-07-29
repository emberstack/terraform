# =============================================================================
# WINDOWS VM PRIMARY DNS SUFFIX (Microsoft.Compute/virtualMachines/extensions)
# =============================================================================
# Sets the guest primary DNS suffix via a CustomScriptExtension, then applies it
# with an ARM restart. The restart (not an in-guest `shutdown`) is deliberate: an
# in-guest reboot is invisible to ARM, so Terraform can't wait on it; azapi blocks
# on the restart LRO until the VM is running again.
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
}

resource "azurerm_virtual_machine_extension" "dns_suffix" {
  name                       = "SetPrimaryDnsSuffix"
  virtual_machine_id         = var.virtual_machine_id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  provision_after_extensions = var.provision_after_extensions
  tags                       = var.tags

  # -ExecutionPolicy is omitted: it governs script files, not the inline
  # -EncodedCommand, so it would be a no-op here.
  settings = jsonencode({
    commandToExecute = "powershell.exe -NoProfile -EncodedCommand ${textencodebase64(local.set_dns_suffix_script, "UTF-16LE")}"
  })
}

# -----------------------------------------------------------------------------
# Apply the suffix with an ARM restart (blocks until the VM is running again)
# -----------------------------------------------------------------------------
# replace_triggered_by keys on .settings so the restart re-fires only when the
# suffix changes - not on tags/handler changes; the action is otherwise inert.

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
    replace_triggered_by = [azurerm_virtual_machine_extension.dns_suffix.settings]
  }

  depends_on = [azurerm_virtual_machine_extension.dns_suffix]
}
