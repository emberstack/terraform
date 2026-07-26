# Azure Custom Role Definition

Terraform module for a single **custom Azure RBAC role definition** (`Microsoft.Authorization/roleDefinitions`).

## Why this exists alongside the AVM module

The Azure Verified Modules ecosystem currently has [`avm-res-authorization-roleassignment`](https://registry.terraform.io/modules/Azure/avm-res-authorization-roleassignment/azurerm/latest) but no resource module for `roleDefinitions`. Community modules (`Pwd9000-ML/custom-role-definitions`, `andrewCluey/custom-role`) cover the gap, but they ship as collection modules with their own opinions about scope handling. This module is intentionally a **single-role primitive** — one role per invocation, the same shape as the rest of the emberstack `res` modules — and pairs with [`azure-ptn-authorization-roledefinition-collection`](../azure-ptn-authorization-roledefinition-collection/) when you need many at once.

## Usage

### Subscription-scoped role

```hcl
module "ddos_join" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-authorization-roledefinition?ref=vX.Y.Z"

  name        = "DDoS Protection Plan Join"
  description = "Read and join VNets to the DDoS Protection Plan."
  scope       = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"

  actions = [
    "Microsoft.Network/ddosProtectionPlans/read",
    "Microsoft.Network/ddosProtectionPlans/join/action",
  ]
}
```

### Management-group-scoped role with explicit assignable scopes

```hcl
module "aks_secrets_reader" {
  source = "..."

  name        = "Azure Kubernetes Service RBAC Secrets Reader"
  description = "Read access to Kubernetes Secrets in AKS clusters via Azure RBAC."
  scope       = data.azurerm_management_group.platform.id

  data_actions = [
    "Microsoft.ContainerService/managedClusters/secrets/read",
  ]

  # Restrict to a subset of subscriptions (default would be the platform MG)
  assignable_scopes = [
    "/subscriptions/${var.workload_subscription_id}",
    "/subscriptions/${var.shared_subscription_id}",
  ]
}
```

### Stable role definition ID (for cross-stack assignments)

```hcl
module "signalr_keys_reader" {
  source = "..."

  name               = "Azure SignalR Service Keys Reader"
  scope              = data.azurerm_management_group.platform.id
  role_definition_id = "11111111-2222-3333-4444-555555555555"

  actions = [
    "Microsoft.SignalRService/SignalR/listKeys/action",
  ]
}
```

Setting a fixed GUID keeps the role's ARM ID stable if the resource is ever recreated, which matters when other Terraform stacks (or external tools) reference the role by full resource ID.

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Notes

- **Action sets vs. lists.** Inputs use `set(string)` so order doesn't drift between plans and duplicates are caught at the type level — Azure RBAC treats actions as a set anyway.
- **`scope` vs. `assignable_scopes`.** `scope` is where the *definition itself* lives (a single RBAC parent). `assignable_scopes` is where it can be *attached* via role assignments. The default (empty → `[scope]`) is right for most cases.
- **Renames force recreate.** Changing `name` recreates the role and breaks any existing assignments. Use `role_definition_id` to pin the GUID if you anticipate renames.
