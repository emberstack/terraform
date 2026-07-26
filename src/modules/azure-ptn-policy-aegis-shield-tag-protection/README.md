# Aegis — Tag-Protection Shield (Pattern)

Turnkey **deny-delete by tag** Azure Policy pattern. Drop in at any scope; any resource (or resource group) carrying the tag **`aegis = deny-delete`** becomes undeletable until the tag is removed or an exemption is granted.

## Why this exists alongside the AVM module

The AVM ecosystem provides building blocks (`avm-ptn-policyassignment`) but no opinionated pattern for tag-based deletion guards. This module composes [`azure-res-policy-definition`](../azure-res-policy-definition/), [`azure-res-policy-set-definition`](../azure-res-policy-set-definition/), and [`azure-res-policy-assignment`](../azure-res-policy-assignment/) into a single drop-in Aegis pattern, with sensible defaults and zero JSON authoring on the caller side.

It uses Azure Policy's `denyAction` effect — the modern, supported way to block deletes.

## The Aegis tag is fixed by contract

| | |
|---|---|
| **Tag name** | `aegis` |
| **Trigger value** | `deny-delete` |
| **Comparison** | case-insensitive (`toLower`) |

Everything in that table is **part of the pattern's contract** — none of it is configurable. Every Aegis-protected resource across every consumer of this module uses exactly the same tag and value, so operators can grep, audit, and reason about protection consistently.

The only assignment-time knobs are `effect` (`DenyAction` or `Disabled`), `enforce`, `not_scopes`, the non-compliance message, and where the definitions/initiative are published.

## What it deploys

Two policy definitions, bundled into one initiative, applied via one assignment:

1. **`aegis-shield-tagged-resource-deny-delete`** (mode `Indexed`)
   Denies delete on individual resources matching the tag. Includes `cascadeBehaviors.resourceGroup = "deny"` — deleting the *parent* resource group is also blocked while the resource is shielded.

2. **`aegis-shield-tagged-resource-group-deny-delete`** (mode `All`)
   Denies delete on resource groups that themselves carry the tag. A separate definition is required because mode `Indexed` does not evaluate resource groups.

3. **Initiative `aegis`** — bundles the two definitions so a single assignment covers both axes.

4. **Assignment** — applied at the configured `scope`.

## Usage

### Subscription-wide

```hcl
module "aegis" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-policy-aegis-shield-tag-protection?ref=vX.Y.Z"

  scope = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
}
```

After `apply`, anything tagged `aegis = deny-delete` (case-insensitive) refuses delete.

### Tenant-root management group, definitions co-located

```hcl
module "aegis" {
  source = "..."

  scope                      = "/providers/Microsoft.Management/managementGroups/tenant-root"
  policy_management_group_id = "/providers/Microsoft.Management/managementGroups/tenant-root"
}
```

### Resource-group scope, with an exclusion

```hcl
module "aegis_workload" {
  source = "..."

  scope = azurerm_resource_group.workload.id

  not_scopes = [
    azurerm_storage_account.scratch.id,  # transient resources never shielded
  ]
}
```

### Pause without unassigning

```hcl
module "aegis" {
  source = "..."

  scope  = "/subscriptions/${var.subscription_id}"
  effect = "Disabled"
}
```

### Exempt a specific resource

Pair with [`azure-res-policy-exemption`](../azure-res-policy-exemption/):

```hcl
module "exempt_legacy_workload" {
  source = "../azure-res-policy-exemption"

  name                 = "exempt-legacy-workload"
  scope                = azurerm_resource_group.legacy.id
  policy_assignment_id = module.aegis.assignment_id
  exemption_category   = "Mitigated"
  description          = "Legacy workload retired under change ticket INFRA-1234."
  expires_on           = "2026-09-30T23:59:59Z"
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Notes

- **Why two policies, not one.** Mode `Indexed` only evaluates resources that support tags + location, which excludes resource groups. Mode `All` covers resource groups but loses the `cascadeBehaviors` that lets a tagged child block its parent RG's delete. The pattern uses `Indexed` for resources (with cascade) and `All` for resource groups themselves.
- **No `Audit` effect.** `denyAction` reports non-compliance only when an actual delete is attempted and blocked, so an audit-only mode would emit no useful signal. Use `Disabled` if you need to switch the shield off temporarily.
- **Tag inheritance.** Azure does not auto-inherit tags from a resource group to its child resources. Pair with the built-in `Inherit a tag from the resource group if missing` policy if you need tag bubble-down.
