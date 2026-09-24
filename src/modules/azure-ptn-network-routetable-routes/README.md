# Azure Route Table Routes (Pattern)

Map-driven routes in an **existing** route table. The table is owned somewhere else; this module only
adds routes to it, so several configurations can each contribute their own routes to one shared table.

## Why this exists alongside the AVM module

[`Azure/avm-res-network-routetable/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-network-routetable/azurerm/latest)
creates routes alongside the table it creates, which ties every route to that one owner. Its
`modules/route` submodule reaches an existing table, but manages one route per call. The common
platform case is a shared table — a hub's firewall or gateway subnet table, say — where routes for
peerings, partner links and on-premises ranges are each owned by a different configuration and arrive
as a map.

The `routes` input mirrors AVM's `routes` object field for field, so a route moves between the two
without being rewritten.

## Usage

### Forced tunnelling through a firewall appliance

```hcl
module "routes" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-network-routetable-routes?ref=vX.Y.Z"

  route_table_resource_id = module.route_table.resource_id

  routes = {
    default = {
      name                   = "default-to-firewall"
      address_prefix         = "0.0.0.0/0"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = "10.0.0.4"
    }

    monitor = {
      name           = "azure-monitor-direct"
      address_prefix = "AzureMonitor"
      next_hop_type  = "Internet"
    }
  }
}
```

### Two owners, one table

Each configuration calls the module against the same `route_table_resource_id` with its own map. Route
names must not collide across the two — ARM holds one namespace per table, and neither module can see
the other's routes.

```hcl
# peerings configuration
module "peering_routes" {
  source = "..."

  route_table_resource_id = var.shared_route_table_resource_id

  routes = {
    spoke_a = {
      name                   = "spoke-a"
      address_prefix         = "10.10.0.0/16"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = "10.0.0.4"
    }
  }
}

# on-premises configuration
module "onprem_routes" {
  source = "..."

  route_table_resource_id = var.shared_route_table_resource_id

  retry = {
    error_message_regex = ["AnotherOperationInProgress", "RetryableError"]
  }

  routes = {
    datacenter = {
      name           = "datacenter"
      address_prefix = "192.168.0.0/16"
      next_hop_type  = "VirtualNetworkGateway"
    }
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Requirements

- The deploying principal needs `Microsoft.Network/routeTables/routes/write` and
  `Microsoft.Network/routeTables/routes/delete` on the target table (both carried by
  `Network Contributor`).

## Notes

- **State address stability.** Each entry creates `azapi_resource.this["<key>"]`. The key is your IaC
  handle and is not part of the ARM ID — that comes from the table plus `name` — so renaming a key
  recreates the route. On a table carrying live traffic, that is a gap. Pick stable keys.
- **Removing an entry deletes the route.** Unlike the `azapi_update_resource` patterns in this family,
  this module owns real child resources: destroying it, or dropping a key, removes the route from the
  table, and traffic falls back to whatever route matches next.
- **Writes into one table are serialised.** Every route locks `route_table_resource_id`, the same lock
  the azurerm provider takes for `azurerm_route`, so a large map applies one route at a time. The lock
  only spans one Terraform run. When another configuration writes into the same table concurrently, set
  `retry` with a pattern matching the conflict your subscription returns.
- **The table's owner must not manage inline routes.** ARM writes are full replaces, so an owner that
  sends the table's route list — azurerm's inline `route` blocks, or an AzAPI body carrying
  `properties.routes` — removes every route not in its own list, including these. An owner that leaves
  the list unset is safe; AVM's route table module (0.5.0) declares the table without inline routes and
  creates its own as separate resources.
- **`address_prefix` takes a CIDR or a service tag.** CIDRs are validated; service tags are only
  checked for shape, because the list is long, grows, and differs between clouds. A misspelled tag fails
  at apply, not at plan.
- **`VirtualApplianceEcmp` is not supported.** It carries its next hops in a separate `nextHop` object
  that this module does not send, so the type is rejected by validation rather than creating a route
  with no next hop.
- **Apply ordering matters.** The route table must already exist. Place this module downstream of its
  owner.

## Migrating from `azurerm_route`

Resource *types* differ, so `moved` blocks do not apply — Terraform reads the new addresses as
unrelated resources and plans a destroy-and-recreate. Adopt the existing routes instead, one per map
entry:

```bash
terraform state pull > backup.tfstate
terraform state rm 'azurerm_route.<name>["<key>"]'
terraform import 'azapi_resource.this["<key>"]' '<route-table-resource-id>/routes/<route-name>?api-version=2025-07-01'
terraform plan   # expect: No changes
```

The `?api-version=` suffix keeps the import on the module's pinned version, so the first plan does not
show a change that only rewrites `type`. A plan that still shows a destroy means an import did not
land — do not apply it.
