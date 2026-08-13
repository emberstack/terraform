# Role assignments

Five Azure modules expose a `role_assignments` map, and two of them expose a second one per private
endpoint. They all share the same implementation, so this page is the single description of it.

| Module | Map | Scope of the assignment |
|---|---|---|
| [`azure-res-cache-redis`](../src/modules/azure-res-cache-redis/) | `role_assignments` | the cluster |
| | `private_endpoints[*].role_assignments` | that endpoint |
| [`azure-res-signalrservice-signalr`](../src/modules/azure-res-signalrservice-signalr/) | `role_assignments` | the service |
| | `private_endpoints[*].role_assignments` | that endpoint |
| [`azure-res-network-dnszone`](../src/modules/azure-res-network-dnszone/) | `role_assignments` | the zone |
| [`azure-res-network-privatednszone`](../src/modules/azure-res-network-privatednszone/) | `role_assignments` | the zone |
| [`azure-res-policy-assignment`](../src/modules/azure-res-policy-assignment/) | `identity_role_assignments` | the assignment scope, or any scope you name |

`azure-res-policy-assignment` is the odd one out by design: its map grants roles to the assignment's
own system-assigned identity, so a `DeployIfNotExists` or `Modify` policy can remediate. It is not a
general-purpose RBAC input.

## Role names are resolved by a subscription-scope lookup

AzAPI has no equivalent of azurerm's `role_definition_name`. So `role_definition_id_or_name` accepts
either form and the module routes on the leading `/`:

- a value starting with `/` is treated as a role definition resource ID and used as-is
- anything else is looked up by role name against a `Microsoft.Authorization/roleDefinitions` listing

The listing is read once, only when the map is non-empty, and always at the **provider's**
subscription. Built-in roles exist in every subscription, so any built-in name resolves. A **custom**
role defined in a different subscription is not in that listing — pass it as a resource ID.

### A name that does not resolve fails the plan

A value that is neither a resource ID nor a role name present in the listing used to fall through the
lookup unchanged and reach ARM as a bare string in `roleDefinitionId`. ARM rejects it with an error
that names neither the role nor the assignment that carried it — on a map of twenty assignments, that
is a hunt.

Every role-assignment resource therefore carries a `precondition` asserting the value resolved, which
reports the offending map key and the value it was given. The test is that a resolved value is always
an ARM ID and so begins with `/`; the resource-ID form passes untouched, because it already does. A
misspelled role name is now a plan-time error instead of an apply-time one.

For the two per-endpoint maps the message also names the private endpoint, since their state address
is the two keys joined with `-` and the composite alone does not say which endpoint went wrong.

## The assignment name is a GUID, and it is the resource's identity

ARM makes the role assignment's *name* a caller-supplied GUID, and that name is its identity. The
modules therefore generate one:

```hcl
resource "random_uuid" "role_assignment_name" {
  for_each = var.role_assignments
}

name = coalesce(each.value.name, random_uuid.role_assignment_name[each.key].result)
```

Leave `name` unset and you get a stable generated GUID that lives in state and does not churn between
plans. Set it and yours wins. That `coalesce` is what makes adoption possible.

> ⚠️ The name is deliberately **not** derived from the principal ID. A principal that is unknown at
> plan time would force a replacement of the assignment on every run.

## Adopting an assignment that already exists

Whenever a role assignment exists in Azure but not in state — a migration, a hand-made grant, a unit
being split — adopt it rather than letting Terraform create a second one.

```bash
terraform state pull > backup.tfstate
terraform import 'random_uuid.role_assignment_name["<key>"]' '<existing-assignment-guid>'
terraform import 'azapi_resource.role_assignments["<key>"]' '<assignment-resource-id>'
terraform plan   # expect: No changes
```

**Importing `random_uuid` with the existing GUID is the step that matters.** `name` falls back to that
UUID, so the adopted assignment keeps its identity. Skip it and a fresh UUID is generated, the name
changes, ARM treats it as a different assignment — destroy and recreate, with a brief loss of access
on apply. Supplying `role_assignments[*].name` explicitly in configuration achieves the same thing if
you would rather pin it there.

Take the backup. `state rm` is not reversible without it.

A resource with **no** role assignments lands on an outputs-only plan rather than *no changes* after an
import: `import` persists an empty `for_each` output as null instead of `{}`. The settling apply
reports `0 added, 0 changed, 0 destroyed`.

## Keys are state addresses

The map key is your IaC handle. It is also part of the Terraform address, so renaming a key recreates
the assignment.

For the two modules with **per-endpoint** assignments, the address is built by joining the endpoint key
and the assignment key with `-`. Both keys are therefore validated as lower-case snake_case
(`^[a-z0-9]+(_[a-z0-9]+)*$`): a key containing `-` would let two different pairs collide on one
address, since `("a-b", "c")` and `("a", "b-c")` both produce `a-b-c`. A collision silently drops one
assignment out of `for_each`, which on apply destroys a live grant.

## Freshly created principals

ARM validates that the principal exists in the directory, and that lookup fails on a principal
created moments earlier. Set `principal_type = "ServicePrincipal"` to skip it.
`azure-res-policy-assignment` always sends `ServicePrincipal`, since the principal is always the
assignment's own identity.

## Required permissions

The deploying principal needs `Role Based Access Control Administrator` (or equivalent) at the scope
being assigned — plus `Microsoft.Authorization/roleDefinitions/read`, which every reader role already
carries, for the name lookup.
