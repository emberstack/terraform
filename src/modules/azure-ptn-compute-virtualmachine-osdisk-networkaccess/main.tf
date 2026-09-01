# =============================================================================
# VM OS DISK NETWORK ACCESS (Microsoft.Compute/disks)
# =============================================================================
# Closes off network access to a virtual machine's OS disk. The VM is not owned
# here; only its OS disk is touched.
#
# This cannot be done by whatever module creates the VM. `publicNetworkAccess`
# and `networkAccessPolicy` live on Microsoft.Compute/disks, not on the VM's
# storageProfile, so ARM offers no way to set them at VM creation - a
# post-create PATCH against the disk is the only route. AVM's virtual machine
# module has the same gap for the same reason.
#
# WHAT THIS CONTROLS IS EXPORT, not the running machine. ARM describes
# publicNetworkAccess as the "policy for controlling export on the disk" - it
# governs SAS-based download of the disk image. Disabling it does not touch the
# VM's own data path, so a running workload is unaffected. New disks default to
# publicNetworkAccess=Enabled and networkAccessPolicy=AllowAll, which means the
# disk image is exportable by anyone holding the right ARM permission.
#
# The disk ID is resolved from the VM rather than taken as an input, because
# callers have a VM and the OS disk name is server-generated. That also means a
# replaced VM yields a new disk ID, which changes this resource's target and
# re-applies the patch - so a rebuilt machine does not silently come back with
# an exportable disk.
#
# Removing this module does NOT re-open the disk. azapi_update_resource has no
# destroy-time revert; it patches on create and leaves the value in place. Set
# the values you want rather than deleting the module to undo them.
#
# OS disk only. Data disks are separate resources and out of scope.
# =============================================================================

data "azapi_resource" "virtual_machine" {
  type        = "Microsoft.Compute/virtualMachines@2024-07-01"
  resource_id = var.virtual_machine_id

  response_export_values = ["properties.storageProfile.osDisk.managedDisk.id"]
}

locals {
  os_disk_resource_id = data.azapi_resource.virtual_machine.output.properties.storageProfile.osDisk.managedDisk.id

  # networkAccessPolicy and diskAccessId are merged in only when set, so a
  # caller that only wants public access disabled does not silently reset a
  # policy someone else configured.
  properties = merge(
    { publicNetworkAccess = var.public_network_access },
    var.network_access_policy != null ? { networkAccessPolicy = var.network_access_policy } : {},
    var.disk_access_id != null ? { diskAccessId = var.disk_access_id } : {},
  )
}

resource "azapi_update_resource" "os_disk" {
  type        = "Microsoft.Compute/disks@2024-03-02"
  resource_id = local.os_disk_resource_id

  body = {
    properties = local.properties
  }

  retry = var.retry

  response_export_values = [
    "properties.publicNetworkAccess",
    "properties.networkAccessPolicy",
  ]
}
