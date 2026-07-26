# Entra ID Administrative Unit

Creates an Entra ID administrative unit and (optionally) manages its membership and AU-scoped directory role assignments.

Membership is delegated to a submodule (`modules/member`) so members can also be managed independently of the AU itself — useful when the AU and the principals are owned by different teams or different repos.

AU-scoped role assignments are inlined (the `azuread_directory_role_assignment` resource lives directly in this module).

## Usage

### Greenfield: AU + members + role assignments in one shot

```hcl
# Activate the directory role you want to assign at AU scope
resource "azuread_directory_role" "user_administrator" {
  template_id = "fe930be7-5e62-47db-91af-98c3a49a38b1"
}

module "iam_glb" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/entra-res-administrativeunit?ref=vX.Y.Z"

  display_name              = "IAM-GLB"
  description               = "Global IAM administrative unit"
  hidden_membership_enabled = false
  prevent_duplicate_names   = true

  members = {
    eve  = "00000000-0000-0000-0000-000000000001"
    frank = "00000000-0000-0000-0000-000000000002"
  }

  role_assignments = {
    ops_team_user_admin = {
      role_id             = azuread_directory_role.user_administrator.object_id
      principal = "operations-group-object-id"
    }
  }
}
```

### Add members to an existing AU

```hcl
module "iam_glb_members" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/entra-res-administrativeunit/modules/member?ref=vX.Y.Z"

  administrative_unit_object_id = "existing-au-object-id"
  members = {
    eve = "00000000-0000-0000-0000-000000000001"
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Submodules

- [`modules/member`](./modules/member/) — manage members of an existing administrative unit.

## Requirements


The provider must be authenticated with permissions sufficient for the operations requested:

- Creating administrative units → **Privileged Role Administrator** role on the tenant.
- Adding members → AU `Member.ReadWrite.All` directory permission, or owning role.
- Creating role assignments at AU scope → **Privileged Role Administrator**, with the target directory role already activated in the tenant (`azuread_directory_role` resource or `data "azuread_directory_role"` lookup).

## Notes

- The `members` argument on the underlying `azuread_administrative_unit` resource is intentionally not set — membership is managed via separate `azuread_administrative_unit_member` resources in the submodule. Mixing the two methods causes drift.
- `prevent_duplicate_names` is a create-time check; changing it on an existing AU is a no-op.
- Removing one entry from `members` or `role_assignments` only destroys that single resource; the AU itself and the other entries are untouched.
- `role_assignments[*].role_id` is the **object ID** of an *activated* directory role, not the role template ID. Activate a role with `azuread_directory_role { template_id = "..." }` and pass `azuread_directory_role.<name>.object_id` here, or look up an already-activated role via `data "azuread_directory_role"`.
