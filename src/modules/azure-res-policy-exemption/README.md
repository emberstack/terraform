# Azure Policy Exemption

Terraform module for a single **Azure Policy exemption** at any scope (management group, subscription, resource group, or resource).

## Why this exists alongside the AVM module

There is no AVM module for `policyExemptions`. This module is a thin wrapper around the four `azurerm_<scope>_policy_exemption` resources, with the same scope-routing pattern as [`azure-res-policy-assignment`](../azure-res-policy-assignment/) so exemptions and assignments compose cleanly.

## Usage

### Subset exemption inside an initiative

```hcl
module "exempt_legacy_storage_from_https" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-policy-exemption?ref=v0.1.0"

  name                 = "exempt-legacy-storage-https"
  scope                = azurerm_storage_account.legacy.id
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
  scope                = azurerm_resource_group.workload.id
  policy_assignment_id = module.tag_protection_assignment.resource_id
  exemption_category   = "Mitigated"
  description          = "Tag protection compensated by RBAC lock managed in IaC."
}
```

## Inputs

### Required

| Name | Type | Description |
|---|---|---|
| `name` | `string` | Exemption name. |
| `scope` | `string` | ARM ID of the scope. |
| `policy_assignment_id` | `string` | ARM ID of the assignment to exempt from. |
| `exemption_category` | `string` | `Waiver` or `Mitigated`. |

### Optional

| Name | Type | Default | Description |
|---|---|---|---|
| `display_name` | `string` | `null` | Portal display name. |
| `description` | `string` | `null` | Long-form description. |
| `expires_on` | `string` | `null` | RFC 3339 expiry. |
| `policy_definition_reference_ids` | `list(string)` | `null` | Restrict to specific policies in an initiative. |
| `metadata` | `any` | `{}` | Free-form metadata (HCL object). |

## Outputs

| Name | Description |
|---|---|
| `resource_id` | Exemption ARM resource ID. |
| `name` | Exemption name. |
| `scope_kind` | Detected scope kind. |

## Requirements

- Terraform `>= 1.15`
- `hashicorp/azurerm` `>= 4.81, < 5.0`
