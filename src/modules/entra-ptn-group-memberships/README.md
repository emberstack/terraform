# Entra ID Group Memberships

Pattern module for managing arbitrary Entra group memberships — adding principals to groups when the (group, principal) pairs don't fit the "members of one group" shape that [`entra-res-group/modules/member`](../entra-res-group/modules/member/) provides.

Typical use cases:

- Adding a managed identity (or any single principal) to several groups at once.
- Centralized membership ledgers where the membership lifecycle is owned separately from the groups themselves.
- Cross-cutting role/permission grants where a principal needs membership in multiple groups for different reasons.

For the simpler "members of group X" pattern, prefer [`entra-res-group/modules/member`](../entra-res-group/modules/member/) — it's keyed by group, takes a flat `members` map, and composes into the parent group resource.

## Usage

```hcl
module "gha_memberships" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/entra-ptn-group-memberships?ref=v0.1.0"

  group_memberships = {
    gha_in_operators = {
      group_object_id = "11111111-1111-1111-1111-111111111111"
      member          = "22222222-2222-2222-2222-222222222222"
    }
    gha_in_operators_entra = {
      group_object_id = "33333333-3333-3333-3333-333333333333"
      member          = "22222222-2222-2222-2222-222222222222"
    }
    alice_in_operators = {
      group_object_id = "11111111-1111-1111-1111-111111111111"
      member          = "alice@example.com"
    }
  }
}
```

`member` is auto-detected by format:

- UUID → used as `member_object_id` directly.
- UPN (e.g. `alice@example.com`) → resolved via `azuread_user` data source. UPNs only resolve to **users**; groups and service principals must be passed by object ID.

UPN-based entries require the deploying principal to have at least `User.Read.All` Graph permission.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `group_memberships` | `map(object)` | `{}` | Map of `<stable-key> => { group_object_id, member }`. `group_object_id` must be a UUID. `member` is UUID or UPN. |

## Outputs

| Name | Type | Description |
|---|---|---|
| `group_memberships` | `map(object)` | Map of `azuread_group_member` resources, keyed by the input map key. Each entry exposes `id`, `group_object_id`, `member_object_id`. |

## Related modules

- [`entra-res-group`](../entra-res-group/) — the resource module for creating groups; its inline `members` input is the natural place to define membership when the group is being created in the same deployment.
- [`entra-res-group/modules/member`](../entra-res-group/modules/member/) — for adding members to one specific existing group.

## Requirements

- Terraform `>= 1.15`
- `hashicorp/azuread` `>= 3.9, < 4.0`

The provider must be authenticated as a principal with permission to write group membership for the target groups (typically the group's owner, or **Groups Administrator**).
