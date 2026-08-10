# Azure Policy Exemption

Terraform module for a single **Azure Policy exemption** at any scope (management group, subscription, resource group, or resource).

## Why this exists alongside the AVM module

There is no AVM module for `policyExemptions`. This module is a thin wrapper around `Microsoft.Authorization/policyExemptions`, using the same scope-as-`parent_id` handling as [`azure-res-policy-assignment`](../azure-res-policy-assignment/) so exemptions and assignments compose cleanly.

The API version is pinned to `2022-07-01-preview` because no stable version of `policyExemptions` exists — preview is the only version Azure ships.

## Usage

### Subset exemption inside an initiative

```hcl
module "exempt_legacy_storage_from_https" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-policy-exemption?ref=vX.Y.Z"

  name                 = "exempt-legacy-storage-https"
  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/rg-legacy/providers/Microsoft.Storage/storageAccounts/stlegacy"
  policy_assignment_id = module.security_baseline_assignment.resource_id
  exemption_category   = "Waiver"

  policy_definition_reference_ids = ["enforce_https_only"]

  expires_on = "2026-12-31T23:59:59Z"

  metadata = {
    requestedBy = "platform-team"
    ticket      = "INFRA-1234"
  }
}
```

### Mitigated exemption at resource group scope

```hcl
module "exempt_workload_rg" {
  source = "..."

  name                 = "exempt-workload-rg"
  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/rg-workload"
  policy_assignment_id = module.tag_protection_assignment.resource_id
  exemption_category   = "Mitigated"
  description          = "Tag protection compensated by RBAC lock managed in IaC."
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.
