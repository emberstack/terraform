# Entra ID Group Collection

Pattern module that manages a **collection of Entra groups** in a single deployment by fanning out to the singular [`entra-res-group`](../entra-res-group/) resource module for each entry in `var.groups`.

Use this when you want **one Terragrunt deployment / one state file** to own multiple groups that share lifecycle and ownership. For independent lifecycle per group, call the singular `entra-res-group` module directly from separate deployments instead.

## When to use this vs the singular module

| Use this pattern (`group-collection`) | Use the singular (`entra-res-group`) |
|---|---|
| All groups share lifecycle (create / update / destroy together) | Groups have independent lifecycle |
| Same team owns all of them | Different teams own different groups |
| Many small groups (operational batch) | Few large/critical groups (foundational identity) |
| You want one terragrunt apply, one state | You want per-group state and locks |
| Bulk creation/destruction is acceptable | Need to delete/recreate one without disturbing others |

This pattern follows AVM's classification: it's a **pattern module** (`entra-ptn-`), composed from a resource module (`entra-res-`).

## Usage

```hcl
module "ops_groups" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/entra-ptn-group-collection?ref=vX.Y.Z"

  groups = {
    operators = {
      display_name = "ops-operators"
      description  = "Operations team — operator role"

      owners = {
        eve = "00000000-0000-0000-0000-000000000001"
      }
      members = {
        alice = "..."
        bob   = "..."
      }
    }

    readers = {
      display_name = "ops-readers"
      description  = "Operations team — read-only role"

      owners  = { eve = "00000000-0000-0000-0000-000000000001" }
      members = { carol = "..." }
    }

    admins = {
      display_name       = "ops-admins"
      assignable_to_role = true
      owners             = { eve = "00000000-0000-0000-0000-000000000001" }
      members            = { alice = "..." }
    }
  }
}
```

### Consuming the outputs

```hcl
# Reference the operators group's object_id elsewhere
locals {
  ops_operators_id = module.ops_groups.groups["operators"].object_id
}

# Iterate over all groups (e.g., to assign them to an AU)
module "iam_au_members" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/entra-res-administrativeunit/modules/member?ref=vX.Y.Z"

  administrative_unit_object_id = "..."
  members = {
    for k, g in module.ops_groups.groups : k => g.object_id
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Examples

- [`examples/basic`](./examples/basic/) — two security groups with members, demonstrating the output structure.

## Related modules

- [`entra-res-group`](../entra-res-group/) — the singular resource module this pattern composes.
- [`entra-res-administrativeunit`](../entra-res-administrativeunit/) — for AU membership of created groups.

## Requirements


The provider must be authenticated as a principal with permissions to create groups (typically **Groups Administrator** or **Privileged Role Administrator** for role-assignable groups).

## Notes

- This pattern is a **fan-out wrapper**: each `groups[*]` entry is one fully-independent invocation of the resource module. State addresses look like `module.<your-name>.module.group["<key>"].azuread_group.this`.
- Adding or removing a single entry in the map only adds or destroys that one group's resources; the others are untouched (stable `for_each` keys).
- This pattern does not add any new variables or behavior on top of the resource module. If you need to customize, change the resource module or build a new pattern.
- AVM purist note: AVM typically reserves "pattern modules" for heterogeneous compositions (e.g., AKS + monitoring + identity). A "bulk same-resource" pattern like this is pragmatic for Terragrunt's deployment-as-state model but slightly stretches AVM's intent. The classification (`patterns/`) is correct AVM-style.
