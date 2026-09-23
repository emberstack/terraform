# Azure Fabric Capacity

A Microsoft Fabric capacity (`Microsoft.Fabric/capacities`) with its administrators and
capacity-scope role assignments.

## Why this exists alongside the AVM module

[`Azure/avm-res-fabric-capacity/azure`](https://registry.terraform.io/modules/Azure/avm-res-fabric-capacity/azure/latest)
0.1.0 sends `properties.administration.members` sorted and compares that path against what
ARM returns. ARM stores the members as an unordered set and returns them in an order of its
own, so the comparison never settles: the apply succeeds, ARM keeps its order, and the next
plan renders the same reorder. Every plan reports a change, forever.

This module keeps the same input shape and takes the members out of body comparison,
reconciling them through a PATCH instead. See
[Fabric capacity administrators](../../../docs/modules/azure.md#fabric-capacity-administrators)
for the measurements behind that.

It also takes a `resource_group_name` rather than AVM's `parent_id`, matching the rest of
this family.

## Usage

```hcl
module "capacity" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-fabric-capacity?ref=vX.Y.Z"

  name                = "examplefabriccapacity"
  resource_group_name = "rg-example"
  location            = "westeurope"
  sku_name            = "F8"

  administration_members = [
    "alice@example.com",
    "bob@example.com",
  ]

  role_assignments = {
    platform_readers = {
      role_definition_id_or_name = "Reader"
      principal_id               = "00000000-0000-0000-0000-000000000000"
      principal_type             = "Group"
    }
  }

  tags = {
    environment = "production"
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Notes

- **Administration is not RBAC.** `administration_members` governs who administers the
  capacity inside Fabric; `role_assignments` is ARM control-plane RBAC. Granting one does
  not grant the other.
- **Members are reconciled on apply, not detected on plan.** A member added out of band —
  through the Fabric portal, say — does not show as drift. The next apply that changes the
  set overwrites it, because the PATCH sends the configured set whole. Removing the module
  from configuration does not strip the members either; there is simply no PATCH left to
  send.
- **At least one member is required.** The capacities API rejects a create with an empty
  set, so the variable validates it rather than letting the apply fail.
- **Groups are not accepted.** Fabric takes individual principals only — a user principal
  name, or a service principal's object ID.
- **The SKU tier is not configurable.** `Fabric` is the only tier the API accepts; only the
  F SKU varies.
- **Name charset is narrow.** Lowercase letters and digits only — the API rejects hyphens
  and uppercase, which is stricter than most Azure resources.
- **Importing.** `terraform import` gives the provider no configuration to read the API
  version from, so it guesses its newest known version and the read fails against a
  capacity. Pin it in the import ID:

  ```
  terraform import module.capacity.azapi_resource.this \
    '/subscriptions/<sub>/resourceGroups/rg-example/providers/Microsoft.Fabric/capacities/examplefabriccapacity?api-version=2023-11-01'
  ```
