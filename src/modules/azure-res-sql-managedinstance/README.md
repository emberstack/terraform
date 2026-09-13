# Azure SQL Managed Instance

Terraform module for **Azure SQL Managed Instance** (`Microsoft.Sql/managedInstances`). Mirrors the input surface of [`Azure/avm-res-sql-managedinstance/azurerm`](https://github.com/Azure/terraform-azurerm-avm-res-sql-managedinstance) where one exists, and differs in the way that matters most: the instance is created by a **single ARM PUT that already carries the identity, the key and the SKU**.

The AVM module cannot do that. It builds the instance with `azurerm_mssql_managed_instance` and bolts the rest on with post-create `azapi_resource_action` calls, one of which PATCHes the managed identity in *after* the TDE protector has been ordered — so a customer-managed key on a fresh instance always fails with `AzureKeyVaultNoServerIdentity`, and the workaround is to apply once without encryption and again with it. Two passes, on a resource whose create is measured in hours. Here the ordering problem cannot arise.

The module does **not** create the resource group, the subnet, or the key vault grant — pass an existing resource group name via `resource_group_name`, a prepared subnet via `subnet_resource_id`, and grant the primary identity wrap/unwrap on the key before the first apply.

## Usage

### Minimal

```hcl
module "sql_managed_instance" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-sql-managedinstance?ref=vX.Y.Z"

  name                = "my-sql-mi"
  location            = "westeurope"
  resource_group_name = var.resource_group_name
  subnet_resource_id  = var.sql_subnet_resource_id

  sku_name           = "GP_Gen5"
  vcores             = 4
  storage_size_in_gb = 128

  administrator_login          = "superadmin"
  administrator_login_password = var.administrator_login_password # ephemeral
}
```

The subnet must be delegated to `Microsoft.Sql/managedInstances` **and** carry both a route table and a network security group before ARM reports it "Ready for Managed Instance". Neither association is created here, and a create against an unprepared subnet fails after provisioning has already begun.

### Entra-only authentication

ARM requires a SQL login at creation even when Entra-only is switched on immediately afterwards. Once it is on, that password can no longer be reset — the create-time credential is permanent.

```hcl
module "sql_managed_instance" {
  source = "..."

  # ...

  entra_administrator = {
    login     = "IAM-SQL-ADMINS"
    object_id = azuread_group.sql_admins.object_id
  }

  entra_only_authentication_enabled = true
}
```

### Customer-managed TDE with auto-rotation

Pass the same user-assigned identity in both `managed_identities.user_assigned_resource_ids` and `primary_user_assigned_identity_resource_id` — TDE resolves the key through the primary one, and a precondition checks it is also attached.

```hcl
module "sql_managed_instance" {
  source = "..."

  # ...

  managed_identities = {
    user_assigned_resource_ids = [var.tde_identity_resource_id]
  }

  primary_user_assigned_identity_resource_id = var.tde_identity_resource_id

  customer_managed_key = {
    key_vault_key_uri     = var.tde_key_versioned_id
    auto_rotation_enabled = true
  }
}
```

**Pass a versioned key URI.** ARM accepts a versionless one but normalises it, reporting back the versioned form — so a versionless config never matches the response and diffs forever. Rotation is `auto_rotation_enabled`, not the URI shape.

### Threat protection and diagnostics

```hcl
module "sql_managed_instance" {
  source = "..."

  # ...

  advanced_threat_protection_enabled = true

  diagnostic_settings = {
    sentinel = {
      workspace_resource_id = var.log_analytics_workspace_resource_id
      log_groups            = { allLogs = true }
      metric_categories     = { AllMetrics = true }
    }
  }
}
```

`advanced_threat_protection_enabled` and `security_alert_policy.enabled` are two ARM views of one switch. Set them alike or leave the former null — a precondition rejects the contradiction rather than letting an apply write the state twice.

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output carries a description, and CI enforces that.

## ARM spellings, not azurerm's

This module sends the body straight through and compares what ARM returns, so three inputs must name the value ARM stores. The full SKU table is in [the family guide](../../../docs/modules/azure.md#managed-instance-sku-names); in short:

| input | ARM | azurerm spelled it |
|---|---|---|
| `sku_name` | `BC_G8IH`, `GP_G8IH`, `BC_G8IM`, `GP_G8IM` | `BC_Gen8IH`, … (the Gen5 names are unchanged) |
| `backup_storage_redundancy` | `Geo` / `GeoZone` / `Local` / `Zone` | `GRS` / `GZRS` / `LRS` / `ZRS` |
| `proxy_override` | `Redirect` | `Default`, which ARM resolves *to* `Redirect` |

A validation rejects an unknown SKU name and a precondition rejects a vCore count the family does not offer, both listing what is valid.

## Adopting an existing instance

`moved` blocks cannot cross a provider type change, so migrating off the azurerm-based module is state surgery. The shape is the family's usual one — see [Migrating to AzAPI](../../../docs/modules/azure.md#migrating-to-azapi) — with one addition specific to this module:

```bash
terraform state pull > backup.tfstate
terraform state rm 'azurerm_mssql_managed_instance.this' # …and the rest of the old addresses
terraform import 'azapi_resource.this'            '<instance ARM ID>?api-version=2025-01-01'
terraform import 'azapi_resource.administrator[0]' '<instance ARM ID>/administrators/ActiveDirectory?api-version=2025-01-01'
terraform plan
```

**Do not try to import the `azapi_update_resource` addresses** — that resource type has no import implementation and answers *"Resource Import Not Implemented"*. Leave the singletons to create: each is a PATCH, so against an already-correct child it writes nothing. The post-import plan reads `N to add, 1 to change, 0 to destroy`, the `1 to change` being the instance shedding the full ARM body that `import` stored. Verify that change only strips properties ARM re-derives or leaves alone before applying it.

Adoption does not require the SQL password. Omit `administrator_login` and `administrator_login_password` together and the null login is dropped from the request, leaving the one Azure already holds — which matters, because on an Entra-only instance that password can no longer be reset or recovered.

## Notes

- **Five children are singletons ARM creates with the instance** — the Entra-only toggle, the TDE protector, and the three security children — so they are `azapi_update_resource` (a PATCH), not `azapi_resource` (a PUT that would collide on a greenfield apply).
- **`administrators` is not sent inline.** ARM accepts it at create time only and ignores it on update, so the `administrators/ActiveDirectory` child owns it instead.
- **`sku` carries only `name` and `capacity`.** ARM derives `tier` and `family` from the name; omitted properties are not compared, so the derived pair cannot drift.
- **`response_export_values` is scoped deliberately.** The instance response carries `state`, `provisioningState` and `currentBackupStorageRedundancy`, all of which the service moves on its own — exporting everything invites *"Provider produced inconsistent result after apply"*.
- **Timeouts default to 8h** for create, update and delete. AzAPI's 30-minute default would abandon every create mid-flight.
- **Not covered:** managed databases, failover groups, DNS aliases, instance pools, the restore/replica create modes, and private endpoints. A managed instance is reachable in its subnet; an endpoint would only serve to publish the public data endpoint privately.
- **Role assignments** follow the family pattern described in [Role assignments](../../../docs/role-assignments.md). They are control-plane grants — nothing here grants access to data inside the instance.
