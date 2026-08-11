# Aegis — Resource Shield (Pattern)

**Deny-delete by explicit resource ID.** Name the resources you want protected and each one gets its own
Azure Policy assignment refusing delete operations against it.

The explicit counterpart to
[`azure-ptn-policy-aegis-shield-tag-protection`](../azure-ptn-policy-aegis-shield-tag-protection/), which
shields anything carrying the `aegis = deny-delete` tag.

## Why this exists alongside the AVM module

The AVM ecosystem provides building blocks (`avm-ptn-policyassignment`) but no opinionated deletion
guard. This module composes [`azure-res-policy-definition`](../azure-res-policy-definition/) and
[`azure-res-policy-assignment`](../azure-res-policy-assignment/) into one drop-in pattern, with no JSON
authoring on the caller side.

## When to use this rather than the tag shield

| Use | When |
|---|---|
| **this module** | tagging is impractical, or protection must exist **before** the resource does |
| tag shield | you can tag, and you want protection to follow the tag automatically |

That second row is the real reason both exist: a tag-based policy can only evaluate tags that already
exist, so it cannot protect a resource that has not been created yet. Naming the ARM ID up front can.

## What it deploys

1. **One policy definition** — `aegis-shield-resource-deny-delete`, a `denyAction` rule matching a single
   resource by ID, taking that ID as the `protectedResourceId` parameter.
2. **One assignment per protected resource** — each binding the parameter to its own ID.

One definition, N assignments. Adding a resource adds an assignment; it does not touch the definition.

## Usage

### Protect two resources at subscription scope

```hcl
module "aegis_resources" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-policy-aegis-shield-protection?ref=vX.Y.Z"

  scope = "/subscriptions/${data.azapi_client_config.current.subscription_id}"

  protected_resources = {
    state_storage = {
      resource_id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-example/providers/Microsoft.Storage/storageAccounts/stexamplestate"
    }

    platform_vault = {
      resource_id = "/subscriptions/${var.subscription_id}/resourceGroups/rg-example/providers/Microsoft.KeyVault/vaults/kv-example"
      description = "Holds the platform CMK. Deleting it orphans every encrypted resource."
    }
  }
}
```

### Definitions published to a management group, one entry paused

```hcl
module "aegis_resources" {
  source = "..."

  scope                      = "/providers/Microsoft.Management/managementGroups/platform"
  policy_management_group_id = "/providers/Microsoft.Management/managementGroups/platform"

  protected_resources = {
    state_storage = {
      resource_id = var.state_storage_resource_id
    }

    migrating_vault = {
      resource_id = var.legacy_vault_resource_id
      effect      = "Disabled"   # paused without unassigning
    }
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Notes

- **Map keys are assignment names**, so ARM's length limits apply: 1–24 characters at subscription or
  resource scope, 1–64 at management group scope. The key is also the Terraform address — renaming one
  destroys and recreates that assignment, leaving the resource unprotected for the length of the apply.
- **Null means "use the default", and the default differs by field.** `scope`, `effect` and
  `non_compliance_message` fall back to the module-level input of the same name. `display_name`,
  `description` and `enforce` fall back to a built-in literal — there is no module-level input for those
  three to inherit.
- **No `Audit` effect.** `denyAction` reports non-compliance only when a delete is actually attempted and
  blocked, so an audit-only mode would emit no useful signal. Use `effect = "Disabled"` to switch a
  shield off temporarily without unassigning it.
- **Scope changes recreate the assignment.** `scope` becomes the assignment's `parent_id`; the same
  assignment at a subscription and at a resource group are different ARM resources.
- **Exempting a resource.** Pair with [`azure-res-policy-exemption`](../azure-res-policy-exemption/),
  passing the relevant entry from the `assignments` output — or just remove the entry from the map if the
  protection is no longer wanted at all.
- **Protection is only as strong as the assignment.** Anyone able to delete the policy assignment can
  delete the resource afterwards. Shield the assignment's own scope with RBAC.
