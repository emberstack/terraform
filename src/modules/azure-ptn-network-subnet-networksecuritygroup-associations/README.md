# Pattern: Subnet Network Security Group Associations

Associates network security groups with existing subnets without redeclaring the subnets themselves. Classified `ptn` rather than `res` because it does not create or manage a primary Azure resource — it only writes `properties.networkSecurityGroup` on each parent subnet, fanning out over a map input.

## Why this pattern exists

`Azure/avm-res-network-routetable` associates *itself* with subnets through its `subnet_resource_ids` input. `Azure/avm-res-network-networksecuritygroup` has no equivalent: through v0.5.1 it exposes no subnet input and creates no association resource at all. So an NSG association has to be declared on the subnet, which makes the vnet depend on the NSG.

That is fine until the NSG's own rules need the subnet's address prefix — a delegated service's internal node-to-node rules, or an AKS node range:

```
vnet  ──[needs NSG id]──>  nsg
nsg   ──[needs subnet prefix]──>  vnet     ← cycle
```

Moving the association downstream breaks it:

```
vnet  →  nsg  →  this pattern (associates the NSG with the subnet)
```

`azapi_update_resource` is purpose-built for exactly this: it does not create a new Azure resource — it writes a subset of an existing one's properties. ARM offers no property-level PATCH for subnets, so the write is a read-merge-write of the whole subnet; everything not named in `body` is echoed back untouched, including the address prefix, delegations and route table.

## Usage

### Dedicated NSG per subnet

The shape delegated services require — Azure SQL Managed Instance mandates an NSG on its subnet, and forbids sharing it with any other subnet in a peered vnet.

```hcl
module "subnet_nsgs" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-network-subnet-networksecuritygroup-associations?ref=vX.Y.Z"

  subnet_network_security_group_associations = {
    sql_primary = {
      subnet_resource_id                 = module.vnet.subnets["sql_primary"].resource_id
      network_security_group_resource_id = module.sql_primary_nsg.resource_id
    }
    sql_green = {
      subnet_resource_id                 = module.vnet.subnets["sql_green"].resource_id
      network_security_group_resource_id = module.sql_green_nsg.resource_id
    }
  }
}
```

### One shared NSG across several subnets

Repeat the same `network_security_group_resource_id`:

```hcl
module "subnet_nsgs" {
  source = "..."

  subnet_network_security_group_associations = {
    app = {
      subnet_resource_id                 = module.vnet.subnets["app"].resource_id
      network_security_group_resource_id = module.shared_nsg.resource_id
    }
    data = {
      subnet_resource_id                 = module.vnet.subnets["data"].resource_id
      network_security_group_resource_id = module.shared_nsg.resource_id
    }
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Requirements

- The deploying principal must have `Microsoft.Network/virtualNetworks/subnets/write` on each target subnet and `Microsoft.Network/networkSecurityGroups/join/action` on each NSG (both carried by `Network Contributor`).

## Notes

- **No new Azure resource is created.** The Azure REST view is a write of `networkSecurityGroup` on the existing subnet body. Destroying this module does not destroy the subnet or the NSG.
- **Destroying this module leaves the association in place.** `azapi_update_resource` performs no operation on delete, so the last-written value persists with nothing managing it. The same applies to removing a single entry from the map. To detach an NSG you have to write the subnet from its owner, or clear it out of band.
- **The subnet's owner must not clear `networkSecurityGroup`.** Whatever module owns the subnet writes its body on every apply, so it can revert this one. Which behaviour you get depends on the owner:
  - **`azurerm_subnet`** — `network_security_group_id` was removed from that resource in azurerm 4.x in favour of `azurerm_subnet_network_security_group_association`, so the subnet resource itself no longer competes for the property.
  - **AzAPI, including AVM** — check whether the owner sends the property as null when it has no NSG input of its own. `Azure/avm-res-network-virtualnetwork` builds the subnet body with `networkSecurityGroup` derived from its own `network_security_group` input, so an owner that leaves that input unset sends null and reverts this module. Guard it with `lifecycle { ignore_changes = [body.properties.networkSecurityGroup] }` on the owner's subnet resource — refresh pulls the live value into state and `ignore_changes` keeps it, so the owner's write carries the association back. You cannot add a `lifecycle` block to a module you do not control, so in practice this means an override file merged into the owner's module directory.

  An owner that omits the key entirely is safe without a guard: ARM treats an absent property as "no change". Confirm which of the two you have before relying on it.
- **Concurrent writes to one vnet collide — use `retry`.** ARM serialises writes against a virtual network, so entries targeting subnets of the *same* vnet fan out into concurrent PUTs and one can fail against an operation already in progress. Set `retry` with a pattern matching the conflict your subscription returns rather than lowering `-parallelism` for the whole configuration:

  ```hcl
  retry = {
    error_message_regex = ["AnotherOperationInProgress", "RetryableError"]
  }
  ```

  A map whose subnets all live in different vnets does not need it.
- **Apply ordering matters.** This module assumes both the subnet and the NSG already exist. Place this leaf downstream of both.
- **Conflicts with an inline NSG in the subnet body.** If you also set the owner's `network_security_group` input for the same subnet, both will fight over the same ARM property on every apply. Use one or the other; the inline form is fine when the NSG's rules do not depend on the subnet, this module is for breaking cycles.
