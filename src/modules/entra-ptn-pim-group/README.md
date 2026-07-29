# Entra ID PIM for Groups

Pattern module that brings an **existing** Entra group under Privileged Identity Management and manages
its role management policies, eligibility schedules and active assignment schedules.

The group itself is not created here — pass an object ID from
[`entra-res-group`](../entra-res-group/) or [`entra-ptn-group-collection`](../entra-ptn-group-collection/).

## Requirements

> **App-only authentication is mandatory.** This module needs the Microsoft Graph permissions
> `RoleManagementPolicy.ReadWrite.AzureADGroup`, `PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup`
> and `PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup`. Neither the Azure CLI nor the Azure
> PowerShell first-party client is preauthorized for them, so `use_cli` / `use_powershell`
> authentication fails with `403 PermissionScopeNotGranted` **regardless of the signed-in user's
> directory role** — being Global Administrator is not enough. Authenticate with a client secret,
> certificate or OIDC against an application granted those permissions.

Those permissions are tenant-wide and cannot be scoped to a single group. A credential holding them can
make any principal eligible for any PIM-managed group and can rewrite any group's activation policy.
Treat it accordingly.

## Usage

```hcl
module "operator_pim" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/entra-ptn-pim-group?ref=vX.Y.Z"

  group_object_id = "00000000-0000-0000-0000-000000000001"

  policies = {
    member = {
      activation = {
        maximum_duration      = "P1D"
        require_justification = true
        authentication        = { method = "mfa" }
        approvers             = {} # explicitly no approval
      }

      eligible_assignments = {
        expiration = "permitted" # allows the permanent eligibility below
      }
    }
  }

  eligibility = {
    roster = {
      principal       = "11111111-1111-1111-1111-111111111111"
      assignment_type     = "member"
    }
  }
}
```

## Adoption, not creation

Entra materialises a role management policy for every group on demand, and
`azuread_group_role_management_policy` takes over the existing one. Terraform reports it as "will be
created" and counts it in `N to add`, but no new directory object appears. **A first apply overwrites
whatever the portal had** for every attribute the module sets.

That is why nothing in `variables.tf` carries a default — an unset attribute passes through as `null`,
which the provider treats as "inherit the adopted value". Three levels:

| You write | Effect |
|---|---|
| block omitted | not managed — existing value survives |
| block present, attribute omitted | not managed — existing value survives |
| attribute set | managed — overwrites existing value |

The two exceptions are `active_assignments` and `eligible_assignments`, which take a **mandatory**
`expiration`, because the provider requires an expiry decision whenever the block exists.

## Collapsed conflict pairs

Several provider attributes are mutually exclusive. Rather than expose both sides and validate the
combination, each pair is collapsed into a single knob and both sides are derived:

| Not exposed | One knob |
|---|---|
| `require_multifactor_authentication` + `required_conditional_access_authentication_context` | `activation.authentication.method` — `mfa` / `conditional_access` / `none` |
| `expiration_required` + `expire_after` | `expiration` — `permitted` / `required` / `P15D`…`P365D` |
| `require_approval` + `approval_stage` | `approvers` — omitted / `{}` / populated |
| `permanent_assignment` + `duration` | `duration` — omitted means permanent |

The unused side of a pair is passed as `null`, never `false` — those pairs are `ConflictsWith` in the
provider schema and only `null` reads as absent.

This prevents *writing* a conflicting pair; it cannot guarantee the adopted policy ends up with only
one side set. Switching a live policy from `conditional_access` to `mfa` does not necessarily clear the
stored authentication context.

## Principals: object ID or UPN

`principal` on both schedule maps accepts **either** an Entra object ID (UUID) **or** a user
principal name, auto-detected by format. UPNs are resolved through the `azuread_user` data source,
following the same routing convention as `entra-res-group`.

```hcl
eligibility = {
  alice = { principal = "alice@example.com", assignment_type = "member" }                        # looked up
  crew  = { principal = "11111111-1111-1111-1111-111111111111", assignment_type = "member" }     # used directly
}
```

Two consequences:

- **Values must be known at plan time.** The lookup partitions the maps by value, so a principal
  produced by another resource makes the partition unknown and Terraform rejects the data source's
  `for_each`. Pass an object ID in that case. Map *keys* may be anything static.
- **App-only callers need `User.Read.All`** for the UPN lookup. Object IDs require no directory read,
  so a caller that only ever passes object IDs needs neither.

### A group can be the principal

A principal may be a user **or a group** — and a group has no UPN, so groups are always given as
object IDs. Entra forbids a group as an *active* member of a role-assignable group but permits it as
an *eligible* one; activation then resolves per user, and the roster group never becomes an active
member. This is how a roster group is bound to a role-assignable target without enumerating people
twice.

## Known limitation: `expiration_date` outranks `duration`

The provider builds a schedule request preferring `expiration_date`, then `duration`, then
`permanent_assignment`. `expiration_date` is Optional+Computed and this module never sets it, so once
the API populates it in state, that value wins over a later change here and the schedule will not
converge. Exposing it would reintroduce the conflict pair the design removes, so instead:
`terraform apply -replace=` the schedule address when it needs to change.

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output carries a
description, and CI enforces that.

## Related modules

- [`entra-res-group`](../entra-res-group/) — creates the group this module governs.
- [`entra-ptn-group-collection`](../entra-ptn-group-collection/) — many groups from one map.
