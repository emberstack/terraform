# Pattern: VM OS Disk Network Access

Closes off network access to an existing virtual machine's OS disk. Classified `ptn` rather than `res` because it creates nothing — it writes `publicNetworkAccess`, `networkAccessPolicy` and `diskAccessId` on a disk that already exists.

## Why this pattern exists

These properties live on `Microsoft.Compute/disks`, not on the VM's `storageProfile`, so ARM offers no way to set them when the VM is created. A post-create PATCH against the disk is the only route — AVM's virtual machine module has the same gap, for the same reason.

New managed disks default to `publicNetworkAccess = Enabled` and `networkAccessPolicy = AllowAll`, which means **anyone holding the right ARM permission can export the disk image**.

⚠️ **What this controls is export, not the running machine.** ARM describes `publicNetworkAccess` as the policy for controlling export on the disk — it governs SAS-based download of the image. Disabling it does not touch the VM's own data path, so a running workload is unaffected.

The disk ID is resolved from the VM rather than taken as an input, because callers have a VM and the OS disk name is server-generated. That also means a replaced VM yields a new disk ID, which retargets the patch and re-applies it — so a rebuilt machine does not silently come back exportable.

## Usage

### Disable export on a VM's OS disk

```hcl
module "vm_osdisk_network_access" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-compute-virtualmachine-osdisk-networkaccess?ref=vX.Y.Z"

  virtual_machine_id    = module.vm.resource_id
  public_network_access = "Disabled"
  network_access_policy = "DenyAll"
}
```

### Private export through a disk access resource

`AllowPrivate` routes export through a `Microsoft.Compute/diskAccesses` private endpoint instead of blocking it outright.

```hcl
module "vm_osdisk_network_access" {
  source = "..."

  virtual_machine_id    = module.vm.resource_id
  public_network_access = "Disabled"
  network_access_policy = "AllowPrivate"
  disk_access_id        = var.disk_access_resource_id
}
```

### Public access only, leaving the policy alone

`network_access_policy` and `disk_access_id` are merged into the body only when set, so a caller that only wants public access disabled does not silently reset a policy someone else configured.

```hcl
module "vm_osdisk_network_access" {
  source = "..."

  virtual_machine_id    = module.vm.resource_id
  public_network_access = "Disabled"
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output carries a description, and CI enforces that.

## Requirements

- The VM must already exist; its OS disk ID is read from `properties.storageProfile.osDisk.managedDisk.id`.
- `disk_access_id` is meaningful only with `network_access_policy = "AllowPrivate"`.

## Notes

- **Removing this module does not re-open the disk.** `azapi_update_resource` has no destroy-time revert — it patches on create and leaves the value in place. Set the values you want rather than deleting the module to undo them.
- **OS disk only.** Data disks are separate resources and out of scope.
- **`retry` is exposed** for the same reason it is elsewhere in the family: a disk attached to a VM mid-operation can reject the PATCH transiently.
