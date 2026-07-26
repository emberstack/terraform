# Azure Custom Role Definition Collection (Pattern)

Map-driven wrapper around [`azure-res-authorization-roledefinition`](../azure-res-authorization-roledefinition/). Declare a map of custom RBAC roles in one place; the module fans out one resource-module invocation per entry and stitches the outputs back into a single keyed map.

## Why this exists alongside the AVM module

There is no AVM resource module for `roleDefinitions` (only for role *assignments*). Custom roles are typically managed in bulk at a single management-group scope, so a collection wrapper is the natural shape — one `for_each`, one map of role specs, one output map keyed back. Pairs cleanly with the AVM `avm-res-authorization-roleassignment` module on the consumption side.

## Usage

### Tenant-root MG, single shared scope

```hcl
module "platform_roles" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-authorization-roledefinition-collection?ref=vX.Y.Z"

  scope = data.azurerm_management_group.tenant_root.id

  role_definitions = {
    network_manager_reader = {
      name        = "Network Manager Reader"
      description = "Read-only access to Azure Virtual Network Manager."

      actions = [
        "Microsoft.Network/networkManagers/read",
        "Microsoft.Network/networkManagers/*/read",
        "Microsoft.Network/networkManagers/listDeploymentStatus/action",
      ]
    }

    ddos_protection_plan_join = {
      name        = "DDoS Protection Plan Join"
      description = "Read and join VNets to the DDoS Protection Plan."

      actions = [
        "Microsoft.Network/ddosProtectionPlans/read",
        "Microsoft.Network/ddosProtectionPlans/join/action",
      ]
    }

    aks_rbac_secrets_reader = {
      name        = "Azure Kubernetes Service RBAC Secrets Reader"
      description = "Read access to Kubernetes Secrets via Azure RBAC."

      data_actions = [
        "Microsoft.ContainerService/managedClusters/secrets/read",
      ]
    }
  }
}
```

### Mixed scopes (per-entry override)

```hcl
module "roles" {
  source = "..."

  scope = data.azurerm_management_group.platform.id  # default for entries that don't override

  role_definitions = {
    network_reader_platform = {
      name    = "Platform Network Reader"
      actions = ["Microsoft.Network/*/read"]
    }

    workload_specific_reader = {
      name    = "Workload Reader"
      scope   = "/subscriptions/${var.workload_subscription_id}"  # overrides module scope
      actions = ["Microsoft.Resources/subscriptions/resourceGroups/read"]
    }
  }
}
```

### Consume from an `azurerm_role_assignment`

```hcl
resource "azurerm_role_assignment" "ddos_join" {
  scope              = azurerm_virtual_network.workload.id
  role_definition_id = module.platform_roles.role_definitions.ddos_protection_plan_join.resource_id
  principal_id       = data.azurerm_user_assigned_identity.workload.principal_id
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Notes

- **State address stability.** Each entry creates `module.<name>.module.role_definition["<key>"].azurerm_role_definition.this`. Renaming a key recreates the role and breaks downstream assignments — pick stable keys.
- **Scope changes recreate.** Both the per-entry `scope` and the module-level default change the role's anchor; flipping it forces a recreate. The `role_definition_id` pin lets you keep the GUID stable across recreates if assignments elsewhere reference it directly.
- **Map keys vs. role names.** The map key is your IaC handle (snake_case, free choice); `name` is what shows up in the Azure portal and what `azurerm_role_assignment.role_definition_name` would match. They are independent — pick keys that are stable across renames of the human-facing name.
