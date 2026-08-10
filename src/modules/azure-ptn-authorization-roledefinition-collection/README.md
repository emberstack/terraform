# Azure Custom Role Definition Collection (Pattern)

Map-driven wrapper around [`azure-res-authorization-roledefinition`](../azure-res-authorization-roledefinition/). Declare a map of custom RBAC roles in one place; the module fans out one resource-module invocation per entry and stitches the outputs back into a single keyed map.

## Why this exists alongside the AVM module

There is no AVM resource module for `roleDefinitions` (only for role *assignments*). Custom roles are typically managed in bulk at a single management-group scope, so a collection wrapper is the natural shape — one `for_each`, one map of role specs, one output map keyed back. Pairs cleanly with the AVM `avm-res-authorization-roleassignment` module on the consumption side.

## Usage

### Tenant-root MG, single shared scope

```hcl
module "platform_roles" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-authorization-roledefinition-collection?ref=vX.Y.Z"

  scope = "/providers/Microsoft.Management/managementGroups/tenant-root"

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

  scope = "/providers/Microsoft.Management/managementGroups/platform"  # default for entries that don't override

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

### Assign a role the module created

`resource_id` is the scope-independent form, which is exactly what a role assignment's
`role_definition_id` expects:

```hcl
resource "azapi_resource" "ddos_join" {
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = "0b1f6471-e0ba-4d1c-9b1a-6a4a4e1d0f3c"  # any stable GUID
  parent_id = var.workload_vnet_resource_id

  body = {
    properties = {
      principalId      = var.workload_identity_principal_id
      principalType    = "ServicePrincipal"
      roleDefinitionId = module.platform_roles.role_definitions.ddos_protection_plan_join.resource_id
    }
  }
}
```

The module itself requires only `azapi` and `random`. If your estate assigns roles through `azurerm` or
an AVM module instead, pass the same `resource_id` — it is provider-agnostic by design.

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Notes

- **State address stability.** Each entry creates `module.<name>.module.role_definition["<key>"].azapi_resource.this`. Renaming a key recreates the role and breaks downstream assignments — pick stable keys.
- **Scope changes recreate.** Both the per-entry `scope` and the module-level default change the role's anchor; flipping it forces a recreate. The `role_definition_id` pin lets you keep the GUID stable across recreates if assignments elsewhere reference it directly.
- **Map keys vs. role names.** The map key is your IaC handle (snake_case, free choice); `name` is what shows up in the Azure portal and what a role assignment's `role_definition_name` would match. They are independent — pick keys that are stable across renames of the human-facing name.
- **Use `resource_id`, not `scoped_resource_id`.** Each entry exposes the role in ARM's scope-independent form (`/providers/Microsoft.Authorization/roleDefinitions/<guid>`), which is what a role assignment's `role_definition_id` expects. `scoped_resource_id` carries the anchoring management group and does not compose that way.
