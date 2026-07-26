# Azure Policy Definition

Terraform module for a single custom **Azure Policy definition** (`Microsoft.Authorization/policyDefinitions`).

## Why this exists alongside the AVM module

The Azure Verified Modules ecosystem currently has no resource module for `policyDefinitions`. The Microsoft `Azure/policy-definition/azurerm` module is community-maintained and accepts `policy_rule` only as a stringified JSON blob — fine for hand-built rules, awkward for compositions where you want to reference Terraform values inside the rule.

This module:

- accepts `policy_rule`, `parameters`, and `metadata` as **HCL values** (the module handles `jsonencode`),
- supports both **subscription** (default) and **management group** scope via `management_group_id`,
- exposes the same minimal output surface as the rest of the emberstack policy modules so they compose cleanly.

## Usage

### Minimal (subscription-scoped)

```hcl
module "deny_unmanaged_disks" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-policy-definition?ref=vX.Y.Z"

  name         = "deny-unmanaged-disks"
  display_name = "Deny unmanaged disks"
  description  = "Block creation of unmanaged disks."

  policy_rule = {
    if = {
      allOf = [
        { field = "type", equals = "Microsoft.Compute/virtualMachines" },
        { field = "Microsoft.Compute/virtualMachines/storageProfile.osDisk.managedDisk.id", exists = "false" }
      ]
    }
    then = {
      effect = "[parameters('effect')]"
    }
  }

  parameters = {
    effect = {
      type = "String"
      metadata = {
        displayName = "Effect"
        description = "Audit or Deny."
      }
      allowedValues = ["Audit", "Deny", "Disabled"]
      defaultValue  = "Deny"
    }
  }

  metadata = {
    category = "Compute"
    version  = "1.0.0"
  }
}
```

### Scoped to a management group

```hcl
module "tag_required" {
  source = "..."

  name                = "require-environment-tag"
  display_name        = "Require environment tag"
  management_group_id = data.azurerm_management_group.platform.id

  policy_rule = { ... }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.
