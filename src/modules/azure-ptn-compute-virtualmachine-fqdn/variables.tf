variable "virtual_machine_id" {
  description = "Resource ID of the Windows virtual machine whose in-guest primary DNS suffix this extension sets."
  type        = string

  validation {
    condition     = can(regex("/providers/Microsoft.Compute/virtualMachines/", var.virtual_machine_id))
    error_message = "virtual_machine_id must be a Microsoft.Compute/virtualMachines resource ID."
  }
}

variable "dns_suffix" {
  description = "Primary DNS suffix to write in-guest, e.g. westeurope.cloudapp.azure.com, so the machine's FQDN matches the public DNS name of its IP. Any lowercase DNS domain is accepted."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", var.dns_suffix))
    error_message = "dns_suffix must be a valid lowercase DNS domain (e.g. westeurope.cloudapp.azure.com)."
  }
}

variable "provision_after_extensions" {
  description = "Names of same-VM extensions this suffix step must provision after — the guest agent holds it (and its reboot) until they finish. Empty means no ordering constraint. Example: [\"AADLoginForWindows\"], so the reboot cannot land mid Entra-join."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "tags" {
  description = "Tags applied to the VM extension."
  type        = map(string)
  default     = {}
  nullable    = false
}
