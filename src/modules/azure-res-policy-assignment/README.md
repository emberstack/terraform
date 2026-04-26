# Azure Policy Assignment

Terraform module for a single **Azure Policy assignment** — works at any scope (management group, subscription, resource group, or specific resource) and handles the system-assigned identity + remediation role assignments in one place.

## Why this exists alongside the AVM module

The Azure AVM ecosystem provides [`Azure/avm-ptn-policyassignment/azurerm`](https://registry.terraform.io/modules/Azure/avm-ptn-policyassignment/azurerm/latest), but it is a *pattern* module — opinionated about non-compliance messaging and assumes a specific identity flow. This module is a **resource module**: a thin, predictable wrapper around the four `azurerm_<scope>_policy_assignment` resources, with the awkward bits (scope routing, identity setup, and the role assignments needed by DINE/Modify policies) handled internally.

Highlights:

- **Auto-routes scope**. Pass any ARM resource ID via `scope`; the module dispatches to the correct underlying resource.
- **Identity + roles in one place**. Set `managed_identities.system_assigned = true` and `identity_role_assignments = { ... }` and the module wires the principal ID through to `azurerm_role_assignment` automatically.
- **HCL-native parameters**. `parameters`, `metadata`, etc. accept HCL objects — no manual `jsonencode`.

## Usage

### Audit-only assignment at subscription scope

```hcl
module "audit_unmanaged_disks" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-policy-assignment?ref=v0.1.0"

  name                 = "audit-unmanaged-disks"
  display_name         = "Audit unmanaged disks"
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  policy_definition_id = module.deny_unmanaged_disks.resource_id

  enforce = false  # audit-only

  parameters = {
    effect = { value = "Audit" }
  }
}
```

### DeployIfNotExists with remediation identity

```hcl
module "deploy_log_analytics_agent" {
  source = "..."

  name                 = "deploy-la-agent"
  display_name         = "Deploy Log Analytics agent on VMs"
  scope                = "/subscriptions/${var.workload_subscription_id}"
  policy_definition_id = data.azurerm_policy_definition_built_in.deploy_la_agent.id
  location             = "westeurope"

  managed_identities = {
    system_assigned = true
  }

  parameters = {
    logAnalytics = { value = azurerm_log_analytics_workspace.platform.id }
  }

  identity_role_assignments = {
    contributor_on_workload = {
      role_definition_id_or_name = "Contributor"
      # scope defaults to the assignment scope; override here when the
      # remediation identity must write outside it.
    }
    log_analytics_contributor_on_la = {
      role_definition_id_or_name = "Log Analytics Contributor"
      scope                      = azurerm_log_analytics_workspace.platform.id
    }
  }
}
```

### Resource-group scope with not_scopes and a non-compliance message

```hcl
module "deny_public_blob" {
  source = "..."

  name                 = "deny-public-blob"
  scope                = azurerm_resource_group.workload.id
  policy_definition_id = module.deny_public_blob_def.resource_id

  not_scopes = [
    azurerm_storage_account.public_assets.id,
  ]

  non_compliance_messages = [
    {
      content = "Storage accounts in this resource group must disable public blob access. Contact #infra if you need an exemption."
    },
  ]
}
```

## Inputs

### Required

| Name | Type | Description |
|---|---|---|
| `name` | `string` | Assignment name. |
| `scope` | `string` | ARM ID of the assignment scope (management group, subscription, resource group, or resource). |
| `policy_definition_id` | `string` | ARM ID of the policy definition or initiative. |

### Optional — display

| Name | Type | Default | Description |
|---|---|---|---|
| `display_name` | `string` | `null` | Portal display name. |
| `description` | `string` | `null` | Long-form description. |

### Optional — behavior

| Name | Type | Default | Description |
|---|---|---|---|
| `enforce` | `bool` | `true` | When false, runs in audit-only mode. |
| `not_scopes` | `list(string)` | `[]` | Sub-scopes to exclude. |
| `parameters` | `any` | `{}` | Parameter values, as HCL. |
| `metadata` | `any` | `{}` | Assignment metadata, as HCL. |
| `non_compliance_messages` | `list(object)` | `[]` | Optional non-compliance messages. |
| `overrides` | `list(object)` | `[]` | Effect overrides. |
| `resource_selectors` | `map(list(object))` | `{}` | Resource selectors keyed by selector name. |

### Optional — identity

| Name | Type | Default | Description |
|---|---|---|---|
| `location` | `string` | `null` | Required when `system_assigned = true`. |
| `managed_identities` | `object({system_assigned, user_assigned_resource_ids})` | both empty | MI configuration. |
| `identity_role_assignments` | `map(object)` | `{}` | Roles granted to the system-assigned identity. |

## Outputs

| Name | Description |
|---|---|
| `resource_id` | Assignment ARM resource ID. |
| `name` | Assignment name. |
| `scope_kind` | Detected scope kind. |
| `system_assigned_mi_principal_id` | Principal ID of the SA identity (if any). |
| `identity_role_assignments` | Map of role-assignment details keyed by input key. |

## Requirements

- Terraform `>= 1.15`
- `hashicorp/azurerm` `>= 4.81, < 5.0`

## Notes

- **UAI role management.** When attaching a user-assigned identity, manage role assignments on the UAI itself — they outlive any single policy assignment, and `identity_role_assignments` here only targets the system-assigned identity.
- **Scope routing.** The module fans out to one of the four `azurerm_<scope>_policy_assignment` resources. State addresses are stable per scope kind, so changing `scope` to a different kind is a recreate.
