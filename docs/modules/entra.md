# Entra ID

Modules on the `hashicorp/azuread` provider.

## Modules

| Module | What it manages |
|---|---|
| [`entra-res-group`](../../src/modules/entra-res-group/) | Group, its owners, and optional atomic placement into an administrative unit (+ [`modules/member`](#member-submodules)) |
| [`entra-res-administrativeunit`](../../src/modules/entra-res-administrativeunit/) | Administrative unit and AU-scoped directory role assignments (+ [`modules/member`](#member-submodules)) |
| [`entra-res-application`](../../src/modules/entra-res-application/) | Application registration and its service principal — custom or from a gallery template — with optional app roles, group and optional claims, client secret, claims mapping policy, SAML single sign-on and user/group assignments |
| [`entra-res-serviceprincipal`](../../src/modules/entra-res-serviceprincipal/) | Service principal for an application registered elsewhere — a Microsoft first-party or another tenant's multi-tenant application — optionally adopting one that already exists ([`prevent_destroy` is hardcoded](#prevent_destroy-on-service-principals)) |
| [`entra-ptn-group-collection`](../../src/modules/entra-ptn-group-collection/) | Many groups from one map — delegates to `entra-res-group` |
| [`entra-ptn-group-memberships`](../../src/modules/entra-ptn-group-memberships/) | Arbitrary (group, principal) pairs, for membership managed independently of any group |
| [`entra-ptn-pim-group`](../../src/modules/entra-ptn-pim-group/) | Brings an existing group under PIM — role management policies, eligibility and active assignment schedules |

`entra-ptn-group-collection` is the only module in the repository with an
[`examples/basic/`](../../src/modules/entra-ptn-group-collection/examples/basic/).

## Principals: object ID or UPN

Everywhere a principal is named — owners, members, application user assignments — the input is a
`map(string)` that accepts **either** an Entra object ID (UUID) **or** a user principal name. The
value is partitioned by regex: UUIDs are used directly, UPNs are resolved through an `azuread_user`
data source at plan time. Inputs that can only hold groups, such as `entra-res-application`'s
`group_assignments`, take object IDs alone — a group has no UPN to look up.

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

## `prevent_destroy` on service principals

`entra-res-serviceprincipal` carries `lifecycle { prevent_destroy = true }`, and it is not
configurable — the same stance as the [GitHub family](github.md#prevent_destroy-is-hardcoded).

The service principals this module exists for are ones a service depends on: Entra Domain
Services cannot be managed without its *Domain Controller Services* principal. Deleting one breaks
that service, and recreating it does not restore it — the replacement has a new object ID and none
of the old one's app role assignments or consents.

**`terraform destroy` therefore fails on any configuration using the module**, and so does a
`client_id` change, which forces a replacement. To retire a service principal, `terraform state rm`
it and delete it deliberately in Entra.

`entra-res-application` does not do this. A service principal it creates belongs to an application
the same configuration owns, and goes when that application goes.
