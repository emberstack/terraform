# Azure SignalR Service

Terraform module for a single **Azure SignalR Service** (`Microsoft.SignalRService/signalR`), with
network ACL, private endpoints, diagnostic settings, management lock and role assignments.

## Why this exists alongside the AVM module

`Azure/avm-res-signalrservice-signalr` is *Proposed* rather than published, so there is no AVM module
to wrap. This one mirrors the AVM interface shapes anyway — `name`, `location`, `parent_id`, `tags`,
`lock`, `managed_identities`, `role_assignments`, `private_endpoints`, `diagnostic_settings` — so a
consumer that later moves to AVM is not rewriting call sites.

It is the widest module in the family: it uses all four AzAPI resource kinds (`azapi_resource`,
`azapi_update_resource`, `azapi_resource_action`, and both data sources), and it is the only one with a
`lifecycle { ignore_changes }` guard.

## Usage

### Minimal

```hcl
module "signalr" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-signalrservice-signalr?ref=vX.Y.Z"

  name      = "signalr-example"
  location  = "westeurope"
  parent_id = var.resource_group_resource_id
  sku_name  = "Standard_S1"
}
```

### Entra-only auth, private access

```hcl
module "signalr" {
  source = "..."

  name      = "signalr-example"
  location  = "westeurope"
  parent_id = var.resource_group_resource_id
  sku_name  = "Premium_P1"

  local_auth_enabled            = false  # the default; access keys are refused
  public_network_access_enabled = false

  managed_identities = {
    system_assigned = true
  }

  private_endpoints = {
    default = {
      subnet_resource_id            = var.private_endpoints_subnet_resource_id
      private_dns_zone_resource_ids = [var.signalr_private_dns_zone_resource_id]
    }
  }

  network_acl = {
    default_action = "Deny"
    public_network = {
      allowed_request_types = ["ClientConnection"]
    }
    private_endpoints = {
      default = {
        allowed_request_types = ["ClientConnection", "ServerConnection", "RESTAPI", "Trace"]
      }
    }
  }
}
```

### Upstream endpoints (Serverless mode)

```hcl
module "signalr" {
  source = "..."

  # ...
  service_mode = "Serverless"

  upstream_endpoints = {
    orders = {
      url_template              = "https://example.com/api/{event}"
      hub_pattern               = "orders"
      managed_identity_audience = "api://example-orders"
    }
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Notes

- **Access keys are opt-in on the output.** `include_access_keys` defaults to `false`. Reading keys
  costs an extra `listKeys` action and a wider permission requirement, so the `access_keys` output is
  null until you ask for it. With `local_auth_enabled = false` the keys are inert anyway.
- **`local_auth_enabled` defaults to `false`.** Entra ID only. Set it to `true` only when a caller
  cannot yet use passwordless auth.
- **The network ACL is a second write, and it is guarded.** ARM returns `networkACLs` on the service
  body, so the service resource carries `ignore_changes = [body.properties.networkACLs]` and the ACL is
  written by a sibling `azapi_update_resource`. Without that guard an import would pull the live ACL
  into the service body and the next write would drop it — resetting the service to default-allow.
- **A greenfield apply with both `network_acl` and `private_endpoints` needs two runs.** The ACL
  references each endpoint's *connection name*, which ARM only assigns once the endpoint exists. The
  first apply creates the endpoints; the second writes the ACL. The connection-name data source
  deliberately carries **no** `depends_on` — adding one would make its result unknown at plan whenever
  the service has a pending change, which crashes the provider inside the ACL body.
- **Role assignments** — both the service-scope map and the per-endpoint maps — follow the family
  pattern described in [Role assignments](../../../docs/role-assignments.md), including why the
  per-endpoint keys must be snake_case.
- **`upstream_endpoints[*].managed_identity_audience` is an audience, not an identity.** It becomes
  ARM's `auth.managedIdentity.resource`, which lands in the `aud` claim of the issued token — the
  portal labels it *"Audience in the issued token"*. Which identity is used comes from the service's own
  `managed_identities` configuration.
- **`ignore_null_property` is not set on the ACL update.** `azapi_update_resource` does not offer it, so
  a caller that omits `network_acl.public_network` sends an explicit null for `publicNetwork` against a
  property ARM returns populated.
- **RG creation is out of scope.** Pass an existing resource group via `parent_id`.
