# =============================================================================
# SUBNET NETWORK SECURITY GROUP ASSOCIATIONS
# =============================================================================
# Associates network security groups with existing subnets without redeclaring
# the subnets themselves. No new Azure resource is created — only each existing
# subnet's `properties.networkSecurityGroup` is written.
#
# This pattern exists because `Azure/avm-res-network-networksecuritygroup` has
# no subnet input and creates no association resource, unlike
# `Azure/avm-res-network-routetable` and its `subnet_resource_ids`. The
# association therefore has to be declared on the subnet, which forces the vnet
# to depend on the NSG — and that closes a cycle whenever the NSG's own rules
# are derived from the subnet it protects (a delegated service's subnet range,
# an AKS node range):
#
#   vnet  ──[needs NSG id]──>  nsg
#   nsg   ──[needs subnet prefix]──>  vnet     ← cycle
#
# Moving the association downstream breaks it:
#
#   vnet  →  nsg  →  this pattern (associates the NSG with the subnet)
#
# Each entry carries its own `network_security_group_resource_id`, so one call
# can span many NSGs — the many-NSGs × many-subnets matrix needs no special
# handling.
#
# ARM exposes no property-level PATCH for subnets, so this is a read-merge-write
# of the whole subnet. Everything not named in `body` is echoed back untouched,
# including the address prefix, delegations and route table.
#
# ARM serialises writes against a virtual network, so several entries targeting
# subnets of the SAME vnet fan out into concurrent PUTs that can collide with an
# operation already in progress. `var.retry` is here for that — set it with a
# pattern matching the conflict your subscription returns rather than lowering
# parallelism for the whole configuration.
#
# The subnet's owner must not clear `networkSecurityGroup` on its own writes.
# Whether it would depends on the owner's provider and on whether it sends the
# property as null — see the README, which covers both the azurerm and AzAPI
# cases.
# =============================================================================

resource "azapi_update_resource" "this" {
  for_each = var.subnet_network_security_group_associations

  resource_id = each.value.subnet_resource_id
  type        = "Microsoft.Network/virtualNetworks/subnets@2025-09-01"
  body = {
    properties = {
      networkSecurityGroup = {
        id = each.value.network_security_group_resource_id
      }
    }
  }

  retry = var.retry

  response_export_values = ["properties.networkSecurityGroup.id"]
}
