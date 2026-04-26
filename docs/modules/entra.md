# Entra ID

4 modules on `hashicorp/azuread` (`>= 3.9, < 4.0`), plus two nested submodules.

## Modules

| Module | What it manages |
|---|---|
| [`entra-res-group`](../../src/modules/entra-res-group/) | Group, its owners, and optional atomic placement into an administrative unit (+ [`modules/member`](#member-submodules)) |
| [`entra-res-administrativeunit`](../../src/modules/entra-res-administrativeunit/) | Administrative unit and AU-scoped directory role assignments (+ [`modules/member`](#member-submodules)) |
| [`entra-ptn-group-collection`](../../src/modules/entra-ptn-group-collection/) | Many groups from one map — delegates to `entra-res-group` |
| [`entra-ptn-group-memberships`](../../src/modules/entra-ptn-group-memberships/) | Arbitrary (group, principal) pairs, for membership managed independently of any group |

`entra-ptn-group-collection` is the only module in the repository with an
[`examples/basic/`](../../src/modules/entra-ptn-group-collection/examples/basic/).

## Principals: object ID or UPN

Everywhere a principal is named — owners, members — the input is a `map(string)` that accepts
**either** an Entra object ID (UUID) **or** a user principal name. The value is partitioned by regex:
UUIDs are used directly, UPNs are resolved through an `azuread_user` data source at plan time.

```hcl
owners = {
  alice = "alice@example.com"                            # resolved via Graph
  bob   = "00000000-0000-0000-0000-000000000000"         # used directly
}
```

The map **key** is the resource address and the output key. Keys are yours to choose; pick stable ones.

### The unknown-at-plan-time edge

This pattern has one sharp edge, and it bites hard.

The partition is a `for` expression filtered on the *value*. If any value comes from another resource
— a service principal created in the same apply, say — the filtered map is unknown at plan time and
`for_each` fails outright with *"the for_each value depends on resource attributes that cannot be
determined until apply"*.

The modules are written to avoid this: **resource `for_each` is keyed on the static input map**, and
the UUID-vs-UPN decision happens inside the resource body:

```hcl
resource "azuread_group_member" "this" {
  for_each = var.members                                  # static keys

  group_object_id = var.group_object_id
  member_object_id = (
    can(regex(local.uuid_pattern, each.value))
    ? each.value
    : data.azuread_user.this[each.value].object_id        # decision in the body
  )
}
```

Only the `azuread_user` data source takes a value-derived `for_each`, because a data source failing to
plan is recoverable in a way a resource address is not.

If you add a principal input to a module here, follow that shape. Filtering the map and then
`for_each`-ing the filtered result is the bug.

## Member submodules

Both `entra-res-group` and `entra-res-administrativeunit` expose membership through a nested
`modules/member` submodule rather than the parent's inline collection attribute.

> **Do not set both.** The parent resources deliberately leave `azuread_group.members` and the AU
> `members` attribute unset. Terraform and Graph will fight over ownership if you manage membership
> inline *and* through the submodule, producing drift on every plan that never converges. Read the
> banner in the parent's `main.tf`.

Use the submodule (or `entra-ptn-group-memberships`) when membership is owned by a different
configuration than the group — which is the usual reason the split exists.

## Two collections that *are* set inline

`entra-res-group` deliberately manages two things on the parent resource. Both have a reason beyond
convenience:

- **Owners.** A group must always have at least one owner, and if `owners` is unset the provider
  auto-assigns whichever principal ran the apply. That is a footgun in CI and in production — the
  pipeline identity silently becomes a group owner. Managing owners inline makes the set explicit.
- **Administrative unit placement.** When `administrative_unit_ids` is non-empty the group is created
  in the scope of the first AU and added to the rest in a single Graph call. The input is passed as
  `null` rather than `[]` when empty, so it does not conflict with AU membership managed separately.
