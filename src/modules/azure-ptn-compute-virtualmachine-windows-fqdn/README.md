# Pattern: Windows VM Primary DNS Suffix

Writes a Windows VM's in-guest **primary DNS suffix** and applies it with an ARM restart, so the machine's own FQDN matches the DNS name its address answers to. Classified `ptn` rather than `res` because it creates no primary resource — it attaches a run command to a VM it does not own.

## Why this pattern exists

**ARM has no property for this.** The primary DNS suffix is guest state — three registry values under `Tcpip\Parameters` — and `additionalUnattendContent`, the only ARM surface that reaches guest configuration, accepts just `AutoLogon` and `FirstLogonCommands`, and only at provisioning time. An in-guest write is unavoidable; the only choice is which channel carries it.

**A managed run command, not a CustomScriptExtension.** CustomScript is limited to one instance per VM. A module that claims that slot for three registry values locks its caller out of the VM's only general-purpose script channel. Run commands are named child resources, so this one leaves the CustomScript slot free.

**An ARM restart, not an in-guest `shutdown`.** An in-guest reboot is invisible to ARM, so Terraform cannot wait on it.

## What it writes

| registry value | why |
|---|---|
| `Domain` | the active suffix, derived at boot |
| `NV Domain` | the stored suffix — dropping either desynchronizes them |
| `SyncDomainWithMembership` → `0` | so a later domain join does not silently overwrite the suffix with the AD domain name |

All three under `HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters` — the same keys the Computer Name dialog writes.

## Usage

### Match the guest FQDN to a public DNS name

```hcl
module "vm_dns_suffix" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-compute-virtualmachine-windows-fqdn?ref=vX.Y.Z"

  virtual_machine_id = module.vm.resource_id
  location           = "westeurope"
  dns_suffix         = "westeurope.cloudapp.azure.com"
}
```

### Write now, reboot later

With `reboot = false` the module only writes the registry; the suffix stays inactive until the VM is rebooted by other means. Useful when the restart has to be scheduled.

```hcl
module "vm_dns_suffix" {
  source = "..."

  virtual_machine_id = module.vm.resource_id
  location           = "westeurope"
  dns_suffix         = "corp.example.com"
  reboot             = false
}
```

### Ordering against a domain join

Run commands carry no `provisionAfterExtensions`, so sequencing is the caller's `depends_on`. Under Terraform that is the stronger guarantee anyway — an extension resource does not return until it reports `Succeeded`, so the restart cannot land mid-join.

```hcl
module "vm_dns_suffix" {
  source = "..."

  # ...

  depends_on = [azurerm_virtual_machine_extension.entra_join]
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output carries a description, and CI enforces that.

## Requirements

- A **Windows** VM with a running, ready VM agent.
- `location` must match the VM's region — a run command is a location-tracked resource.
- The restart is bounded by a 15-minute Terraform timeout.

## Notes

- **The reboot re-fires only when the suffix changes.** `replace_triggered_by` keys on the run command's `body`, which carries the script and therefore the suffix. `name` and `tags` are separate top-level attributes, so editing them does not restart the VM.
- **Expect a one-apply gap after any VM replacement.** A run command is a child resource, so replacing the VM deletes it in ARM while the name-based resource ID Terraform tracks stays identical — that same apply plans no change here, and the rebuilt VM boots without the suffix. The next plan reads a 404, drops the state entry and recreates it.
- **Removing this module unregisters the run command; it does not restore the previous suffix.** Set the suffix you want, or clear it in the guest by hand.
- **`timeout_in_seconds` defaults far below the platform's 90 minutes**, because the script writes three registry values: a run that takes minutes has hung, not slowed.
