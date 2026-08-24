# Azure Private Endpoint

Creates a private endpoint (`Microsoft.Network/privateEndpoints`) against a target owned outside the configuration, with an optional private DNS zone group, management lock and endpoint-scope IAM role assignments.

## Why this exists alongside the AVM module

[`Azure/avm-res-network-privateendpoint/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-network-privateendpoint/azurerm/latest) creates an endpoint, but **hardcodes `is_manual_connection = false`** in its `private_service_connection` block and exposes no `request_message`. That rules out every connection needing the target owner's approval — which is every cross-tenant target: MongoDB Atlas, CloudAMQP, Snowflake, Databricks.

It also accepts only a resource ID, so a service that publishes an **alias** cannot be named at all.

This module keeps the AVM input shape (`name`, `location`, `resource_group_name`, `tags`, `role_assignments`) and adds the manual path, alias targets, and connection-state outputs.

Modules that wrap a private-linkable service — [`azure-res-cache-redis`](../azure-res-cache-redis/), [`azure-res-signalrservice-signalr`](../azure-res-signalrservice-signalr/) — carry their own `private_endpoints` input. Keep using it there; those can reference the target resource directly.

## Usage

### Manual connection to a private link service (cross-tenant)

```hcl
module "atlas_endpoint" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-privateendpoint?ref=vX.Y.Z"

  name                = "dev-mongodbatlas-pe"
  location            = "westeurope"
  resource_group_name = "dev-mongodbatlas"
  subnet_resource_id  = module.vnet.subnets.private_endpoints.resource_id
  tags                = local.tags

  private_connection_resource_id  = "/subscriptions/<their-sub>/resourceGroups/<their-rg>/providers/Microsoft.Network/privateLinkServices/pls_example"
  private_service_connection_name = "pls_example"
  is_manual_connection            = true
}
```

`subresource_names` is deliberately absent: a private link service publishes no group IDs, which is why `az network private-endpoint create` takes no `--group-id` against one.

### Manual connection by alias

When the service owner publishes an alias rather than a resource ID — what `cloudamqp_vpc_connect` returns, for instance:

```hcl
  private_connection_resource_alias = cloudamqp_vpc_connect.this.service_name
  private_service_connection_name   = "spn-cloudamqp-pe"
  is_manual_connection              = true
  request_message                   = "PL"
```

### Automatic connection to a PaaS resource

```hcl
module "registry_endpoint" {
  source = "..."

  name                = "acr-pe"
  location            = "westeurope"
  resource_group_name = "platform-acr"
  subnet_resource_id  = module.vnet.subnets.private_endpoints.resource_id

  private_connection_resource_id = module.registry.resource_id
  subresource_names              = ["registry"]
  private_dns_zone_resource_ids  = [module.privatelink_azurecr_io.resource_id]
}
```

## Approval

`is_manual_connection` selects which of ARM's two mutually exclusive body properties carries the connection:

| | `privateLinkServiceConnections` | `manualPrivateLinkServiceConnections` |
|---|---|---|
| `is_manual_connection` | `false` (default) | `true` |
| Approved | on creation | out of band, by the target's owner |
| Needs | write access on the target | nothing — the request is queued |
| Extra input | — | optional `request_message`, capped at 140 chars by ARM |

Both are always sent, one populated and one empty — an ARM write is a full replace, so omitting the unused one would strand the previous connection when the flag is flipped. Fuller treatment in [Azure → Manual connection approval](../../../docs/modules/azure.md#manual-connection-approval).

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Related modules

- [`azure-res-network-privatednszone`](../azure-res-network-privatednszone/) — the zone to pass into `private_dns_zone_resource_ids`.
- [`azure-ptn-network-privatednszone-records`](../azure-ptn-network-privatednszone-records/) — for a target that publishes no FQDN, where the record must be written by hand against the endpoint's IP.

## Requirements

- The deploying principal must have:
  - `Network Contributor` (or equivalent) on the resource group hosting the endpoint.
  - `Microsoft.Network/virtualNetworks/subnets/join/action` on the target subnet.
  - `Role Based Access Control Administrator` (or equivalent) on the endpoint, when `role_assignments` is set.
- Approving a manual connection is the **target owner's** action and happens outside Terraform.

## Notes

- **Role assignments** behave the same here as in every module that exposes them — the name lookup, the
  generated GUID name, and how to adopt an assignment that already exists are all described in
  [Role assignments](../../../docs/role-assignments.md).
- **A `Pending` endpoint is a successful apply.** The endpoint exists and holds an address; no traffic crosses it until the owner approves, and a DNS zone group publishes no records before then. Gate downstream work on the `connection_status` output, read at a later refresh — not on the apply having succeeded.
- **Alias and resource ID are the same ARM property.** Both land in `privateLinkServiceId`, which tells them apart by shape. The two inputs exist to document intent and to validate the string; exactly one must be set.
- **`private_ip_address` can stay null.** ARM surfaces the address through the DNS zone group's record sets, falling back to `customDnsConfigs`. A target that publishes neither — typical of a private link service — leaves it null even once approved. Read the endpoint's network interface instead.
- **The endpoint lands in the subnet's subscription.** ARM requires it, so `resource_group_name` resolves against `subnet_resource_id`'s subscription rather than the provider's. The target may live anywhere.
- **RG creation is out of scope.** Place a sibling `resource-group/` leaf upstream — same convention as the AVM modules in the consuming workspace's live tree.
