# Pattern: VM Run Command

Runs one script inside a virtual machine this module does not own, as a **managed run command** (`Microsoft.Compute/virtualMachines/runCommands`). Classified `ptn` rather than `res` because the VM is the primary resource and it belongs to someone else — this attaches a child to it.

## Why this pattern exists

Two reasons, and the second is the important one.

**A managed run command, not a CustomScriptExtension.** CustomScript is limited to **one instance per VM**. A module that claims that slot locks its caller out of the VM's only general-purpose script channel, permanently. Run commands are named child resources — a VM carries as many as it needs.

**Two ARM defaults are wrong for Terraform**, and this module flips both in the safe direction:

| property | ARM default | here | why |
|---|---|---|---|
| `treatFailureAsDeploymentFailure` | `false` | **`true`** | Under ARM's default, `provisioningState` reports only whether the handler managed to *start* the script. A script that throws still applies clean. A module whose whole job is running a script should fail when the script fails. |
| `asyncExecution` | `true` | **`false`** | The PUT completes only once the script has finished. That is what makes the failure default meaningful, and what lets the optional restart land strictly after the script. |

## Usage

### Inline script

```hcl
module "vm_runcommand" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-compute-virtualmachine-runcommand?ref=vX.Y.Z"

  virtual_machine_id = module.vm.resource_id
  location           = "westeurope"
  name               = "install-agent"

  script = <<-PS
    $ErrorActionPreference = 'Stop'
    Write-Output "hello from the guest"
  PS
}
```

Exactly one of `script`, `script_uri` or `command_id` may be set — ARM supports only one source per execution, and variables.tf enforces it.

### A script Azure ships

```hcl
module "vm_enable_remote_ps" {
  source = "..."

  virtual_machine_id = module.vm.resource_id
  location           = "westeurope"
  name               = "enable-remote-ps"
  command_id         = "EnableRemotePS"
}
```

### Parameters, including secrets

```hcl
module "vm_runcommand" {
  source = "..."

  # ...

  parameters = {
    Environment = "production"
  }

  protected_parameters = {
    ApiKey = var.api_key
  }
}
```

`protected_parameters` are write-only — ARM accepts them and never returns them.

### Script plus an ARM restart

```hcl
module "vm_runcommand" {
  source = "..."

  # ...

  reboot         = true
  reboot_timeout = "15m"
}
```

The restart goes through ARM rather than an in-guest `shutdown`, because an in-guest reboot is invisible to ARM and Terraform cannot wait on it. With `reboot = true` the apply blocks until the VM is running again.

### Streaming output beyond 4 KB

The instance view retains only 4 KB of output. For more, stream to append blobs:

```hcl
module "vm_runcommand" {
  source = "..."

  # ...

  output_blob_uri = var.stdout_append_blob_sas_uri
  error_blob_uri  = var.stderr_append_blob_sas_uri
}
```

Both must be of blob type **AppendBlob**, with a SAS granting the right permissions.

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output carries a description, and CI enforces that.

## Requirements

- The VM agent must be running and ready. A not-ready agent is absorbed by [retry](../../../docs/modules/azure.md#agent-readiness).
- `location` must match the VM's region — a run command is a location-tracked resource.
- `run_as_user` must already exist on the VM and hold the access the script needs.

## Notes

- **Ordering is the caller's `depends_on`.** Run commands carry no `provisionAfterExtensions`, and several deployed together execute in **parallel** by default. Sequencing them is the consumer's job, exactly as in an ARM template.
- **Re-running unchanged content means a new resource.** The script executes on create and on any update to this resource; ARM has no "run it again" verb. To re-run identical content, change `name`.
- **Expect a one-apply gap after any VM replacement.** A run command is a child resource, so replacing the VM deletes it in ARM while the name-based resource ID Terraform tracks stays identical — that same apply plans no change here, and the rebuilt VM never runs the script. The next plan reads a 404, drops the state entry and recreates it.
- **Removing this module unregisters the run command**, terminating it if it is still executing. It does not undo whatever the script already did.
- **`timeouts` and `timeout_in_seconds` are different deadlines.** The first is Terraform's, the second bounds the script. The first has to outlast the second.
- **Pinned to API `2024-07-01`.** `scriptShell` (PowerShell 7) and `galleryScriptReferenceId` arrived in `2025-04-01` and are deliberately out of scope — adding either means moving the pin for every consumer.
