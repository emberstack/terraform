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
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-policy-assignment?ref=vX.Y.Z"

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

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Notes

- **UAI role management.** When attaching a user-assigned identity, manage role assignments on the UAI itself — they outlive any single policy assignment, and `identity_role_assignments` here only targets the system-assigned identity.
- **Scope routing.** The module fans out to one of the four `azurerm_<scope>_policy_assignment` resources. State addresses are stable per scope kind, so changing `scope` to a different kind is a recreate.
