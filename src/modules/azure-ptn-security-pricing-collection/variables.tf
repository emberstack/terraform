# -----------------------------------------------------------------------------
# Plans
# -----------------------------------------------------------------------------

variable "pricings" {
  type = map(object({
    tier     = optional(string, "Standard")
    sub_plan = optional(string, null)
    extensions = optional(list(object({
      name                  = string
      enabled               = optional(bool, true)
      additional_properties = optional(map(string), null)
    })), [])
  }))
  default     = {}
  description = <<-EOT
    Defender plans of the provider's subscription, keyed by the plan's ARM name:
    `CloudPosture`, `VirtualMachines`, `KeyVaults`, `Arm`, `SqlServers`,
    `AppServices`, `Api`, `AI`, `Containers`, `StorageAccounts`, `CosmosDbs`,
    `OpenSourceRelationalDatabases`, `SqlServerVirtualMachines`, and so on. A plan
    left out of the map is not managed — it keeps whatever tier it has.

    - `tier`: `Standard` (on) or `Free` (off). Default: `Standard`.
    - `sub_plan`: the plan's variant where it has one, e.g. `P1`/`P2` for
      `VirtualMachines`, `PerKeyVault` for `KeyVaults`, `PerSubscription` for
      `Arm`, `DefenderForStorageV2` for `StorageAccounts`, `P1`–`P5` for `Api`.
    - `extensions`: the plan's extensions, each with `enabled` (default true)
      and the string-valued `additional_properties` some of them take, such as
      `{ ExclusionTags = "[]" }` on `AgentlessVmScanning` or
      `CapGBPerMonthPerStorageAccount` on `OnUploadMalwareScanning`.

    List EVERY extension ARM reports for the plan — the disabled ones included —
    in the order ARM reports them. ARM keeps its own fixed order per plan and
    materialises extensions nobody asked for, and azapi compares lists by
    position, so a shorter or reordered list diffs on every plan. Read the order
    from `GET .../providers/Microsoft.Security/pricings/<plan>`.
  EOT
  nullable    = false

  validation {
    condition     = alltrue([for plan in keys(var.pricings) : can(regex("^[A-Za-z]+$", plan))])
    error_message = "Every pricings key must be a Defender plan's ARM name, such as CloudPosture or VirtualMachines."
  }

  validation {
    condition     = alltrue([for pricing in values(var.pricings) : contains(["Free", "Standard"], pricing.tier)])
    error_message = "pricings[*].tier must be Free or Standard."
  }

  validation {
    condition     = alltrue([for pricing in values(var.pricings) : pricing.tier == "Standard" || (pricing.sub_plan == null && length(pricing.extensions) == 0)])
    error_message = "A Free plan takes no sub_plan and no extensions; they only exist on the Standard tier."
  }

  validation {
    condition     = alltrue([for pricing in values(var.pricings) : length(distinct([for extension in pricing.extensions : extension.name])) == length(pricing.extensions)])
    error_message = "An extension may be listed only once per plan."
  }
}

# -----------------------------------------------------------------------------
# Malware scan results
# -----------------------------------------------------------------------------

variable "malware_scan_results" {
  type = object({
    name                  = string
    workspace_resource_id = string
  })
  default     = null
  description = <<-EOT
    Ships Defender for Storage malware scan results from every blob-capable
    storage account in the subscription (StorageV2, BlobStorage and
    BlockBlobStorage) to a Log Analytics workspace, as the
    `StorageMalwareScanningResults` table. Null leaves them unshipped.

    - `name`: the diagnostic setting's name on each account.
    - `workspace_resource_id`: the destination workspace.

    The accounts are listed at plan time, so an account created later is picked
    up on the next apply. Needs the `StorageAccounts` plan on the Standard tier.
  EOT
}
