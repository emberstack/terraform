# Azure Policy Set Definition (Initiative)

Terraform module for a single custom **Azure Policy initiative** (`Microsoft.Authorization/policySetDefinitions`).

## Why this exists alongside the AVM module

There is no AVM resource module for `policySetDefinitions`. The Microsoft community module accepts `parameters` and `parameter_values` only as JSON strings. This module accepts them as native HCL objects so initiatives can be composed with Terraform expressions referencing other modules' outputs.

It pairs with [`azure-res-policy-definition`](../azure-res-policy-definition/) — the typical pattern is to author policy definitions with that module and bundle them through this one.

## Usage

```hcl
module "tag_protection_initiative" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-policy-set-definition?ref=vX.Y.Z"

  name         = "tag-protection"
  display_name = "Tag-based resource protection"
  description  = "Initiative bundling tag-based deny-delete and required-tag policies."

  parameters = {
    protection_tag_name = {
      type = "String"
      metadata = {
        displayName = "Protection tag name"
        description = "Tag whose presence marks a resource as protected."
      }
      defaultValue = "platform-protected"
    }
    effect = {
      type          = "String"
      allowedValues = ["Audit", "Deny", "Disabled"]
      defaultValue  = "Deny"
    }
  }

  policy_definition_references = {
    deny_delete_protected = {
      policy_definition_id = module.def_deny_delete_protected.resource_id
      parameter_values = {
        protection_tag_name = { value = "[parameters('protection_tag_name')]" }
        effect              = { value = "[parameters('effect')]" }
      }
    }
  }

  metadata = {
    category = "Tags"
    version  = "1.0.0"
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.
