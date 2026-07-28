# =============================================================================
# WINDOWS VM PRIMARY DNS SUFFIX + REBOOT
# =============================================================================
# Sets the Windows *primary DNS suffix* via a CustomScriptExtension, then
# reboots, so the machine's own FQDN matches the public DNS name of its IP.
# Without it the guest FQDN stays the bare hostname, and anything that issues a
# ticket for the name you typed (Entra RDP being the motivating case) fails
# because the two names differ.
#
# The public IP and its DNS label are the CALLER's to create and attach - this
# module only touches the guest. provision_after_extensions holds the suffix
# step (and its reboot) until the named extensions finish, so it cannot land
# mid Entra-join. That is a stronger guarantee than depends_on, which only
# orders the ARM calls.
# =============================================================================

locals {
  # Deferred so the extension reports success to Azure before the box goes down.
  reboot_delay_seconds = 60

  # Written to HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters - the
  # same keys the Computer Name dialog writes. SyncDomainWithMembership=0
  # mirrors unticking "Change primary DNS suffix when domain membership
  # changes". Idempotent: once the suffix is in place the script exits without
  # rebooting.
  set_dns_suffix_script = <<-PS
    $ErrorActionPreference = 'Stop'
    $suffix = '${var.dns_suffix}'
    $key    = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    $current = (Get-ItemProperty -Path $key -Name 'NV Domain' -ErrorAction SilentlyContinue).'NV Domain'
    if ($current -eq $suffix) {
      Write-Output "Primary DNS suffix already '$suffix' - nothing to do."
      exit 0
    }
    Set-ItemProperty -Path $key -Name 'Domain'                   -Value $suffix -Type String
    Set-ItemProperty -Path $key -Name 'NV Domain'                -Value $suffix -Type String
    Set-ItemProperty -Path $key -Name 'SyncDomainWithMembership' -Value 0       -Type DWord
    Write-Output "Primary DNS suffix set to '$suffix' (was '$current'). Rebooting in ${local.reboot_delay_seconds}s."
    shutdown /r /t ${local.reboot_delay_seconds} /c "Applying primary DNS suffix"
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

  # No -ExecutionPolicy flag: execution policy governs script *files*, not the
  # inline script that -EncodedCommand runs, so it would be a no-op here.
  settings = jsonencode({
    commandToExecute = "powershell.exe -NoProfile -EncodedCommand ${textencodebase64(local.set_dns_suffix_script, "UTF-16LE")}"
  })
}
