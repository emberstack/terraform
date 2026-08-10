# Azure Policy Assignment

Terraform module for a single **Azure Policy assignment** — works at any scope (management group, subscription, resource group, or specific resource) and handles the system-assigned identity + remediation role assignments in one place.

## Why this exists alongside the AVM module

The Azure AVM ecosystem provides [`Azure/avm-ptn-policyassignment/azurerm`](https://registry.terraform.io/modules/Azure/avm-ptn-policyassignment/azurerm/latest), but it is a *pattern* module — opinionated about non-compliance messaging and assumes a specific identity flow. This module is a **resource module**: a thin, predictable wrapper around `Microsoft.Authorization/policyAssignments`, with the awkward bits (scope handling, identity setup, and the role assignments needed by DINE/Modify policies) handled internally.

Highlights:

- **Any scope, one resource**. Pass any ARM resource ID via `scope`; it becomes the assignment's `parent_id`, so management group, subscription, resource group and resource scopes all share one code path.
- **Identity + roles in one place**. Set `managed_identities.system_assigned = true` and `identity_role_assignments = { ... }` and the module wires the principal ID through to the role assignments automatically.
- **HCL-native parameters**. `parameters`, `metadata`, etc. accept HCL objects — no manual `jsonencode`.

## Usage

### Audit-only assignment at subscription scope

```hcl
module "audit_unmanaged_disks" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-policy-assignment?ref=vX.Y.Z"

  name                 = "audit-unmanaged-disks"
  display_name         = "Audit unmanaged disks"
  scope                = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
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
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/${var.deploy_la_agent_definition_guid}"
  location             = "westeurope"

  managed_identities = {
    system_assigned = true
  }

  parameters = {
    logAnalytics = { value = var.platform_workspace_resource_id }
  }

  identity_role_assignments = {
    contributor_on_workload = {
      role_definition_id_or_name = "Contributor"
      # scope defaults to the assignment scope; override here when the
      # remediation identity must write outside it.
    }
    log_analytics_contributor_on_la = {
      role_definition_id_or_name = "Log Analytics Contributor"
      scope                      = var.platform_workspace_resource_id
    }
  }
}
```

### Resource-group scope with not_scopes and a non-compliance message

```hcl
module "deny_public_blob" {
  source = "..."

  name                 = "deny-public-blob"
  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/rg-workload"
  policy_definition_id = module.deny_public_blob_def.resource_id

  not_scopes = [
    "/subscriptions/${var.subscription_id}/resourceGroups/rg-workload/providers/Microsoft.Storage/storageAccounts/stpublicassets",
  ]

  non_compliance_messages = [
    {
      content = "Storage accounts in this resource group must disable public blob access. Contact #infra if you need an exemption."
    },
  ]
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Notes

- **UAI role management.** When attaching a user-assigned identity, manage role assignments on the UAI itself — they outlive any single policy assignment, and `identity_role_assignments` here only targets the system-assigned identity.
- **Scope changes recreate.** `scope` is the assignment's `parent_id`, which forces replacement — an assignment at a subscription and the same assignment at a resource group are different ARM resources. The Terraform address does not move, but the resource is still destroyed and recreated, so a deny-effect assignment is unenforced for the length of the apply.
