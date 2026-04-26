# Entra ID Group

Creates an Entra ID group (security or mail-enabled) and (optionally) manages its membership.

Membership is delegated to a submodule (`modules/member`) so members can be managed independently of the group itself — useful when the group and the members are owned by different teams or different repos.

Owners are managed inline on the group resource: groups must always have at least one owner, and unsetting `owners` causes the provider to auto-assign the deploying principal (a footgun in CI/prod). The module **requires** at least one explicit owner.

## Usage

### Security group with members

```hcl
module "ops_group" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/entra-res-group?ref=v0.1.0"

  display_name = "ops-engineers"
  description  = "Operations engineers"

  owners = {
    eve = "00000000-0000-0000-0000-000000000001"
  }
  members = {
    alice = "..."
    bob   = "..."
  }
}
```

### Role-assignable security group

Set `assignable_to_role = true` to make the group eligible to receive Entra directory roles.

```hcl
module "ops_admins" {
  source = "..."

  display_name       = "ops-admins"
  assignable_to_role = true
  owners             = { eve = "..." }
  members            = { alice = "..." }
}
```

### Microsoft 365 (Unified) group

```hcl
module "engineering" {
  source = "..."

  display_name  = "Engineering"
  types         = ["Unified"]
  mail_enabled  = true
  mail_nickname = "engineering"
  visibility    = "Private"

  owners  = { eve = "..." }
  members = { alice = "...", bob = "..." }
}
```

### Group placed in administrative units at creation

```hcl
module "iam_glb_admins" {
  source = "..."

  display_name             = "iam-glb-admins"
  administrative_unit_ids  = ["00000000-0000-0000-0000-000000000003"]

  owners  = { eve = "..." }
  members = { alice = "..." }
}
```

### Dynamic membership group

```hcl
module "all_engineers" {
  source = "..."

  display_name     = "all-engineers"
  security_enabled = true

  owners = { eve = "..." }

  dynamic_membership = {
    enabled = true
    rule    = "(user.department -eq \"Engineering\")"
  }

  # members must be empty when dynamic_membership is set — enforced by validation
}
```

### Add members to an existing group

```hcl
module "ops_group_members" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/entra-res-group/modules/member?ref=v0.1.0"

  group_object_id = "existing-group-object-id"
  members = {
    carol = "..."
    dave  = "..."
  }
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `display_name` | `string` | — | **Required.** 1–256 characters. |
| `description` | `string` | `null` | Up to 1024 characters. |
| `mail_enabled` | `bool` | `false` | At least one of `mail_enabled` or `security_enabled` must be `true`. |
| `security_enabled` | `bool` | `true` | At least one of `mail_enabled` or `security_enabled` must be `true`. |
| `mail_nickname` | `string` | `null` | Required when `mail_enabled = true` or `types` includes `"Unified"`. |
| `assignable_to_role` | `bool` | `false` | When `true`, the group is eligible to receive Entra directory roles. **Immutable after creation.** |
| `prevent_duplicate_names` | `bool` | `false` | Create-time check only. |
| `visibility` | `string` | `null` | One of `Private`, `Public`, `HiddenMembership`. |
| `types` | `set(string)` | `[]` | Use `["Unified"]` for M365 groups. |
| `behaviors` | `set(string)` | `[]` | e.g. `AllowOnlyMembersToPost`, `HideGroupInOutlook`. |
| `administrative_unit_ids` | `list(string)` | `[]` | AUs the group should belong to (atomic placement at creation). |
| `dynamic_membership` | `object({enabled, rule})` | `null` | When set, `members` must be empty. |
| `owners` | `map(string)` | — | **Required, ≥1 entry.** Map of `<stable-key> => <owner-object-id>`. |
| `members` | `map(string)` | `{}` | Map of `<stable-key> => <member-object-id>`. |

## Outputs

| Name | Type | Description |
|---|---|---|
| `object_id` | `string` | Entra object ID. Use as `principal_object_id` when assigning roles. |
| `display_name` | `string` | Display name. |
| `mail` | `string` | Email address (if `mail_enabled`). |
| `mail_nickname` | `string` | Mail alias. |
| `members` | `map(object)` | Map of `azuread_group_member` resources, keyed by the input map key. |

## Submodules

- [`modules/member`](./modules/member/) — manage members of an existing group.

## Related modules

- [`entra-res-administrativeunit`](../entra-res-administrativeunit/) — administrative scopes (groups can be members of AUs; use `administrative_unit_ids` here for atomic placement at creation).

## Requirements

- Terraform `>= 1.15`
- `hashicorp/azuread` `>= 3.9, < 4.0`

The provider must be authenticated as a principal with permissions to create groups (typically **Groups Administrator** or **Privileged Role Administrator** for role-assignable groups).

## Notes

- **Owners are inline, members are submodule.** Different ownership patterns: groups always have ≥1 owner, but members come and go independently. The submodule pattern lets membership be managed by a different repo / team than the group itself.
- The `members` argument on the underlying `azuread_group` resource is intentionally not set — membership is managed via separate `azuread_group_member` resources in the submodule. Mixing the two methods causes drift.
- `prevent_duplicate_names` is a create-time check; changing it on an existing group is a no-op.
- Removing one entry from `members` only destroys that single membership; the group and the other members are untouched.
- `assignable_to_role = true` is **immutable** after creation. Decide upfront whether the group needs to be role-assignable.
- `administrative_unit_ids` placement is **atomic** at creation (single Graph call). For ongoing AU membership management of an existing group, use a separate `azuread_administrative_unit_member` resource — but don't combine the two on the same AU/group pair.
