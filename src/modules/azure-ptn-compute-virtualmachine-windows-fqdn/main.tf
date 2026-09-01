# =============================================================================
# WINDOWS VM PRIMARY DNS SUFFIX (Microsoft.Compute/virtualMachines/runCommands)
# =============================================================================
# Writes the guest's primary DNS suffix, then applies it with an ARM restart, so
# the machine's own FQDN matches the DNS name its address answers to.
#
# ARM has no property for this. The primary DNS suffix is guest state — three
# registry values under Tcpip\Parameters — and additionalUnattendContent, the
# only ARM surface that reaches guest configuration, accepts just AutoLogon and
# FirstLogonCommands and only at provisioning time. An in-guest write is
# unavoidable; the choice is which channel carries it.
#
# A managed run command, not a CustomScriptExtension: CustomScript is limited to
# one instance per VM, and a module that claims that slot for three registry
# values locks its caller out of the only general-purpose script channel the VM
# has. Run commands are named child resources — a VM carries as many as it needs
# — so this one leaves the CustomScript slot free.
#
# The restart (not an in-guest `shutdown`) is deliberate: an in-guest reboot is
# invisible to ARM, so Terraform cannot wait on it.
#
# Ordering against another extension — an Entra join, say — is the caller's
# depends_on, not a body property: runCommands carry no provisionAfterExtensions.
# Under Terraform that is the stronger guarantee anyway, because an extension
# resource does not return until it reports Succeeded, so the restart cannot land
# mid-join.
#
# A run command is a child resource: replacing the VM deletes it in ARM while
# the name-based resource ID Terraform tracks stays identical, so that same
# apply plans no change here and the rebuilt VM boots without the suffix. The
# next plan reads a 404, drops the state entry and recreates it — expect a
# one-apply gap after any VM replacement.
#
# Removing this module unregisters the run command; it does not restore the
# previous suffix. Set the suffix you want, or clear it in the guest by hand.
# =============================================================================

locals {
  # HKLM\...\Tcpip\Parameters — the keys the Computer Name dialog writes. 'NV
  # Domain' is the stored value and 'Domain' the active one derived from it at
  # boot — dropping the write to either desynchronizes them — and writing both
  # matches the dialog.
  # SyncDomainWithMembership is cleared so a later domain join does not silently
  # overwrite the suffix with the AD domain name.
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

# -----------------------------------------------------------------------------
# Write the suffix into the guest registry
# -----------------------------------------------------------------------------

resource "azapi_resource" "dns_suffix" {
  type      = "Microsoft.Compute/virtualMachines/runCommands@2024-07-01"
  name      = var.name
  parent_id = var.virtual_machine_id
  location  = var.location
  tags      = var.tags

  body = {
    properties = {
      # Exactly one of script / scriptUri / commandId may be set, so the other
      # two are left out of the body rather than sent as null.
      source = {
        script = local.set_dns_suffix_script
      }

      # Sent explicitly (ARM writes are full replaces): false means the PUT
      # completes only when the script has finished, which is what lets the
      # restart below run strictly after the registry write. True would return
      # at script start, and the reboot could land mid-write.
      asyncExecution = false

      # 2023-03-01 and later. Without it provisioningState reports only whether
      # the handler managed to START the script, so a script that throws still
      # applies clean.
      treatFailureAsDeploymentFailure = true

      timeoutInSeconds = var.timeout_in_seconds
    }
  }
}

# -----------------------------------------------------------------------------
# Apply the suffix with an ARM restart — blocks until the VM is running again
# -----------------------------------------------------------------------------
# replace_triggered_by keys on the run command's body, which carries the script
# (and thus the suffix). It changes iff the script or suffix changes; name and
# tags are separate top-level attributes, not part of body, so they don't
# re-fire it.

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
