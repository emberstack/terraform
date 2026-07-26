# Azure Policy Exemption Collection (Pattern)

Map-driven wrapper around [`azure-res-policy-exemption`](../azure-res-policy-exemption/). Declare a map of exemptions in one place; the module fans out one resource-module invocation per entry and stitches the outputs back into a single keyed map.

## Why this exists alongside the AVM module

There is no AVM module for `policyExemptions`, and the AzureRM provider has four scope-specific resources (`azurerm_<scope>_policy_exemption`). [`azure-res-policy-exemption`](../azure-res-policy-exemption/) already auto-routes a single exemption based on its scope ID. This pattern module is the natural next step: when a deployment needs to declare *many* exemptions (compliance frameworks, mitigated controls, custom-role allowlists, ...) it removes the boilerplate of instantiating the resource module by hand for each one.

## Usage

### Subscription-scoped framework exemptions

```hcl
module "compliance_exemptions" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-policy-exemption-collection?ref=vX.Y.Z"

  exemptions = {
    storage-vnet-se-gdpr = {
      name                            = "storage-vnet-se-gdpr"
      scope                           = "/subscriptions/${var.subscription_id}"
      policy_assignment_id            = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/policyAssignments/gdpr-2016-679"
      exemption_category              = "Mitigated"
      display_name                    = "Private endpoints mitigate VNet service endpoint (GDPR)"
      description                     = "Storage accounts use private endpoints, which provide stronger network isolation than VNet service endpoints."
      policy_definition_reference_ids = ["60d21c4f-21a3-4d94-85f4-b924e6aeeda4"]
    }

    storage-vnet-se-iso27002 = {
      name                            = "storage-vnet-se-iso27002"
      scope                           = "/subscriptions/${var.subscription_id}"
      policy_assignment_id            = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/policyAssignments/iso-27002-2022"
      exemption_category              = "Mitigated"
      display_name                    = "Private endpoints mitigate VNet service endpoint (ISO 27002)"
      description                     = "Storage accounts use private endpoints, which provide stronger network isolation than VNet service endpoints."
      policy_definition_reference_ids = ["60d21c4f-21a3-4d94-85f4-b924e6aeeda4"]
    }
  }
}
```

### Mixed-scope (subscription + per-resource) exemptions

```hcl
locals {
  sub = "/subscriptions/${var.subscription_id}"
  pa  = "${local.sub}/providers/Microsoft.Authorization/policyAssignments"
}

module "compliance_exemptions" {
  source = "..."

  exemptions = merge(
    # Subscription-scoped framework exemptions
    {
      keyvault-secret-expiry-gdpr = {
        name                            = "kv-secret-expiry-gdpr"
        scope                           = local.sub
        policy_assignment_id            = "${local.pa}/gdpr-2016-679"
        exemption_category              = "Mitigated"
        display_name                    = "Access controls mitigate secret expiration (GDPR)"
        description                     = "Secrets store application configuration values..."
        policy_definition_reference_ids = ["98728c90-32c7-4049-8429-847dc0f4fe37"]
      }
    },

    # Resource-scoped exemptions, generated from a map of custom RBAC roles
    {
      for role_key, role in var.custom_roles :
      "custom-rbac-${role_key}-gdpr" => {
        name                            = "rbac-${role_key}-gdpr"
        scope                           = role.id
        policy_assignment_id            = "${local.pa}/gdpr-2016-679"
        exemption_category              = "Mitigated"
        display_name                    = "Least-privilege custom role reviewed (GDPR)"
        description                     = "IaC-managed custom role with minimum required permissions."
        policy_definition_reference_ids = ["a451c1ef-c6ca-483d-87ed-f49761e3ffb5"]
      }
    },
  )
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Notes

- **State address stability.** Each entry creates `module.<name>.module.exemption["<key>"].azurerm_<scope>_policy_exemption.this["<exemption-name>"]`. The inner resources use `for_each = toset([var.name])`, so the final index is the exemption's `name` string, not a numeric `[0]`. Changing an entry's scope kind (e.g. subscription → resource) is a recreate, since it routes to a different resource type. Renaming a key — or the exemption `name` — is also a recreate, so pick stable values for both.
- **Composing with other modules.** Pair with [`azure-ptn-policy-aegis-shield-tag-protection`](../azure-ptn-policy-aegis-shield-tag-protection/) or [`azure-res-policy-assignment`](../azure-res-policy-assignment/): pass `module.<name>.assignment_id` (or any `policy_assignment_id`) into one or more entries here.
