# Azure SQL Logical Server

Terraform module for the **Azure SQL logical server** (`Microsoft.Sql/servers`), with submodules for [elastic pools](modules/elastic-pool/) and [databases](modules/database/). Mirrors the input surface of [`Azure/avm-res-sql-server/azurerm`](https://github.com/Azure/terraform-azurerm-avm-res-sql-server) where one exists, and covers three things that module does not:

1. **TDE auto-rotation.** AVM sets `keyId` inline, which pins a key version. Here the `encryptionProtector` child carries `autoRotationEnabled`, so Azure moves the protector to a new key version on its own.
2. **Server auditing.** AVM declares no auditing resource at all.
3. **The Entra administrator as a child resource**, so it survives updates — see the notes.

The module does **not** create the resource group — pass the name of an existing one via `resource_group_name`.

## Usage

### Minimal

```hcl
module "sql_server" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-sql-server?ref=vX.Y.Z"

  name                = "my-sql-server"
  location            = "westeurope"
  resource_group_name = var.resource_group_name

  administrator_login          = "superadmin"
  administrator_login_password = var.administrator_login_password # ephemeral
}
```

`name` becomes `<name>.database.windows.net`, so it must be globally unique. `public_network_access_enabled` defaults to **false** — reach the server through a private endpoint unless you turn it on deliberately.

### Entra-only authentication

```hcl
module "sql_server" {
  source = "..."

  # ...

  entra_administrator = {
    login     = "IAM-SQL-ADMINS"
    object_id = azuread_group.sql_admins.object_id
  }

  entra_only_authentication_enabled = true
}
```

Omit `administrator_login` entirely and Azure generates a provisioning-only `CloudSA*` account that cannot connect. Enabling Entra-only does not delete existing SQL logins; it only stops them connecting, and it blocks resetting the SQL admin password while it is on.

### Customer-managed TDE with auto-rotation

```hcl
module "sql_server" {
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

**Pass a versioned key URI.** ARM accepts a versionless one but normalises it and reports back the versioned form, so a versionless config never matches the response and diffs forever. The identity must already hold wrap/unwrap on the key — this module does not create that grant, and ARM fails with `AzureKeyVaultNoServerIdentity` without it.

### Auditing

```hcl
module "sql_server" {
  source = "..."

  # ...

  auditing = {
    enabled                = true
    log_monitoring_enabled = true
  }
}
```

⚠️ `log_monitoring_enabled` only *routes* the events. They land nowhere until a diagnostic setting carrying the `SQLSecurityAuditEvents` category exists on the server's **`master` database** — a different scope from `diagnostic_settings` here, and the caller's to create. Auditing that is enabled but shipping nowhere is a common and silent gap.

### Private endpoint, firewall and virtual network rules

```hcl
module "sql_server" {
  source = "..."

  # ...

  private_endpoints = {
    default = {
      subnet_resource_id            = var.private_endpoints_subnet_resource_id
      private_dns_zone_resource_ids = [var.sql_private_dns_zone_resource_id]
    }
  }

  virtual_network_rules = {
    aks = { subnet_resource_id = var.aks_subnet_resource_id }
  }
}
```

A firewall rule with both addresses set to `0.0.0.0` is not a literal range — it is the "Allow Azure services and resources to access this server" switch, and it opens the server to every Azure tenant. The module leaves that to the caller to express, because it should read as the exception it is.

### Elastic pool and databases

```hcl
module "sql_elastic_pool" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-sql-server/modules/elastic-pool?ref=vX.Y.Z"

  name      = "production"
  location  = "westeurope"
  parent_id = module.sql_server.resource_id

  sku = { name = "StandardPool", tier = "Standard", capacity = 100 }
}

module "sql_database" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-sql-server/modules/database?ref=vX.Y.Z"

  name                    = "app-db"
  location                = "westeurope"
  parent_id               = module.sql_server.resource_id
  elastic_pool_resource_id = module.sql_elastic_pool.resource_id

  max_size_gb = 250
}
```

Both take the server's ARM resource ID as `parent_id`, so either can be managed by a configuration that does not own the server. A pooled database must leave `sku` null — the pool supplies the tier — but **`max_size_gb` still applies inside a pool** and is a per-database cap drawn from the pool's shared storage.

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf), and the same pair inside each submodule. Every variable and output carries a description, and CI enforces that.

## Adopting an existing server

`moved` blocks cannot cross a provider type change, so migrating off the azurerm-based module is state surgery. The shape is the family's usual one — see [Migrating to AzAPI](../../../docs/modules/azure.md#migrating-to-azapi) — with one caveat specific to this module:

**Do not try to import the `azapi_update_resource` addresses** (`entra_only_authentication`, `connection_policy`, `encryption_protector`, `auditing`). That resource type has no import implementation and answers *"Resource Import Not Implemented"*. Leave them to create: each is a PATCH, so against an already-correct child it writes nothing, and a post-import plan reading `N to add` is expected.

Import `azapi_resource.this`, `azapi_resource.administrator[0]`, and any firewall or virtual network rules, appending `?api-version=2025-01-01` to each ARM ID. `import` stores ARM's full response in `body`, so the first plan shows the config stripping everything it does not send — read that diff before applying it, and confirm every stripped property is one ARM re-derives or leaves alone.

## Notes

- **Three children are singletons ARM creates with the server** — the connection policy, the TDE protector and the auditing settings — so they are `azapi_update_resource` (a PATCH), not `azapi_resource` (a PUT that would collide with "Resource already exists" on a greenfield apply).
- **`administrators` is not sent inline.** ARM documents it as accepted at create time only — *"if used for server update, it will be ignored or it will result in an error"* — so an Entra admin set inline would silently stop tracking configuration. The `administrators/ActiveDirectory` child owns it.
- **The server key registration is not a resource here.** Setting `keyId` on the server makes ARM register the key, so the module derives the registration's name from the URI rather than declaring a resource that would collide.
- **The admin password goes through `sensitive_body`**, declared `ephemeral`, so it never reaches state or the plan file. AzAPI cannot detect drift in a value it cannot read — that is what `administrator_login_password_version` is for: change it to push a rotated secret.
- **Sizes are GB meaning GiB.** The submodules convert with a factor of 1024³, because Azure says "GB" and means GiB — `100` sends `107374182400`.
- **Backup retention is the reason to manage a database here.** PITR and LTR are separate ARM children that are easy to leave unmanaged; see [the family guide](../../../docs/modules/azure.md#backup-retention-is-the-reason-to-manage-a-database-here).
- **Role assignments** follow the family pattern described in [Role assignments](../../../docs/role-assignments.md), including why the per-endpoint keys must be snake_case.
