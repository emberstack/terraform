# Azure

Modules on the `Azure/azapi` provider. Every module in this family talks to ARM directly, so the
resource shape is the ARM request body: properties use ARM's own casing, a scope is the resource's
`parent_id`, and each `type` carries an explicit API version.

Two consequences worth knowing before you read further. ARM writes are **full replaces** — a property
left out of the body is reset to the service default, so anything with a security or connectivity
consequence is sent explicitly rather than omitted. And there is no provider layer smoothing over ARM's
model, so where ARM splits a thing into parent and child resources, the module does too.

Input shapes mirror [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/) where an
AVM equivalent exists — `name`, `resource_group_name`, `tags`, `role_assignments` — and add what AVM
lacks. Keep new inputs shaped the AVM way.

## Resource modules

| Module | What it manages |
|---|---|
| [`azure-res-authorization-roledefinition`](../../src/modules/azure-res-authorization-roledefinition/) | Custom RBAC role definition |
| [`azure-res-cache-redis`](../../src/modules/azure-res-cache-redis/) | Managed Redis, with private endpoint, diagnostic settings, management lock and role assignments |
| [`azure-res-containerservice-managedcluster`](../../src/modules/azure-res-containerservice-managedcluster/) | AKS managed cluster and its system node pool, with public or private API server, Entra integration, customer-managed keys for node disks and etcd, the policy, secrets-provider and load balancer add-ons, diagnostic settings, lock and role assignments (+ [`modules/agentpool`](#submodule-agentpool)) |
| [`azure-res-fabric-capacity`](../../src/modules/azure-res-fabric-capacity/) | Microsoft Fabric capacity and role assignments, with capacity administrators reconciled out of band ([why](#fabric-capacity-administrators)) |
| [`azure-res-kubernetesconfiguration-extension`](../../src/modules/azure-res-kubernetesconfiguration-extension/) | Cluster extension on AKS, Arc or AKS hybrid, with management lock and role assignments for the extension's identity |
| [`azure-res-network-dnszone`](../../src/modules/azure-res-network-dnszone/) | Public DNS zone and role assignments, optionally writing the delegation NS record into a parent zone |
| [`azure-res-network-privatednszone`](../../src/modules/azure-res-network-privatednszone/) | Private DNS zone and role assignments (+ [`modules/vnet-link`](#submodule-vnet-link)) |
| [`azure-res-network-privateendpoint`](../../src/modules/azure-res-network-privateendpoint/) | Standalone private endpoint against a target owned elsewhere, [automatic or manual](#manual-connection-approval), with DNS zone group, management lock and role assignments |
| [`azure-res-network-routeserver`](../../src/modules/azure-res-network-routeserver/) | Route server (a `virtualHubs` resource with no virtual WAN), with its IP configuration, the public IP it requires, diagnostic settings, lock and role assignments (+ [`modules/bgp-connection`](#submodule-bgp-connection)) |
| [`azure-res-network-virtualnetworkgateway`](../../src/modules/azure-res-network-virtualnetworkgateway/) | VPN or ExpressRoute gateway in an existing `GatewaySubnet`, active-standby or active-active, with BGP and custom APIPA peering addresses, diagnostic settings, lock and role assignments — site-to-site only, so point-to-site and NAT rules are not sent |
| [`azure-res-policy-assignment`](../../src/modules/azure-res-policy-assignment/) | Policy or initiative assignment, [scope-routed](#scope-routing) |
| [`azure-res-policy-definition`](../../src/modules/azure-res-policy-definition/) | Policy definition |
| [`azure-res-policy-exemption`](../../src/modules/azure-res-policy-exemption/) | Policy exemption, [scope-routed](#scope-routing) |
| [`azure-res-policy-set-definition`](../../src/modules/azure-res-policy-set-definition/) | Policy initiative |
| [`azure-res-signalrservice-signalr`](../../src/modules/azure-res-signalrservice-signalr/) | SignalR service, with network ACL, private endpoint, diagnostic settings, lock and role assignments |
| [`azure-res-sql-managedinstance`](../../src/modules/azure-res-sql-managedinstance/) | Azure SQL managed instance, with Entra administrator, Entra-only authentication, customer-managed TDE with auto-rotation, threat protection, vulnerability assessment, diagnostic settings, lock and role assignments — identity, key and SKU all in the create PUT, so a CMK instance needs no second pass ([SKU names](#managed-instance-sku-names)) |
| [`azure-res-sql-server`](../../src/modules/azure-res-sql-server/) | Azure SQL logical server, with Entra administrator, Entra-only authentication, customer-managed TDE with auto-rotation, auditing, connection policy, firewall and virtual network rules, private endpoint, diagnostic settings, lock and role assignments (+ [`modules/elastic-pool`](#submodule-elastic-pool-and-database), [`modules/database`](#submodule-elastic-pool-and-database)) |

## Pattern modules

| Module | What it does |
|---|---|
| [`azure-ptn-authorization-roledefinition-collection`](../../src/modules/azure-ptn-authorization-roledefinition-collection/) | Many role definitions from one map |
| [`azure-ptn-compute-virtualmachine-osdisk-networkaccess`](../../src/modules/azure-ptn-compute-virtualmachine-osdisk-networkaccess/) | Public network access and network access policy on an existing VM's OS disk — a post-create PATCH, because the properties live on the disk rather than the VM's storage profile |
| [`azure-ptn-compute-virtualmachine-runcommand`](../../src/modules/azure-ptn-compute-virtualmachine-runcommand/) | One script inside an existing VM as a managed run command, from inline text, a script URI or the commandId of a script Azure ships, with script failure failing the apply, an optional ARM restart, and a not-ready VM agent absorbed by [retry](#agent-readiness) |
| [`azure-ptn-compute-virtualmachine-windows-fqdn`](../../src/modules/azure-ptn-compute-virtualmachine-windows-fqdn/) | Windows VM in-guest primary DNS suffix, written by a managed run command (so the guest FQDN matches its public DNS name) and applied by an ARM restart the apply blocks on until the VM is running again |
| [`azure-ptn-network-dnszone-records`](../../src/modules/azure-ptn-network-dnszone-records/) | A, AAAA, CAA, CNAME, MX, NS, PTR, SRV and TXT records in an existing public zone |
| [`azure-ptn-network-privatednszone-records`](../../src/modules/azure-ptn-network-privatednszone-records/) | A, AAAA, CNAME, MX, PTR, SRV and TXT records in an existing private zone |
| [`azure-ptn-network-privatednszone-vnet-links`](../../src/modules/azure-ptn-network-privatednszone-vnet-links/) | Virtual network links across many zones |
| [`azure-ptn-network-routetable-routes`](../../src/modules/azure-ptn-network-routetable-routes/) | Routes in an existing route table, so several configurations can share one table, written one at a time under a per-table lock |
| [`azure-ptn-network-subnet-networksecuritygroup-associations`](../../src/modules/azure-ptn-network-subnet-networksecuritygroup-associations/) | Network security group associations on existing subnets, across many NSGs |
| [`azure-ptn-network-virtualnetwork-dnsservers`](../../src/modules/azure-ptn-network-virtualnetwork-dnsservers/) | DNS server list on an existing virtual network |
| [`azure-ptn-policy-aegis-shield-protection`](../../src/modules/azure-ptn-policy-aegis-shield-protection/) | [Aegis](#aegis) deny-delete by explicit resource ID |
| [`azure-ptn-policy-aegis-shield-tag-protection`](../../src/modules/azure-ptn-policy-aegis-shield-tag-protection/) | [Aegis](#aegis) tag-driven deny-delete |
| [`azure-ptn-policy-exemption-collection`](../../src/modules/azure-ptn-policy-exemption-collection/) | Many policy exemptions from one map |

## Scope routing

`azure-res-policy-assignment` and `azure-res-policy-exemption` accept a single `scope` string, which
becomes the resource's `parent_id`. ARM anchors these resources by parent, so one resource covers every
scope kind:

| `scope` looks like | Anchored at |
|---|---|
| `/providers/Microsoft.Management/managementGroups/<mg>` | management group |
| `/subscriptions/<sub>` | subscription |
| `/subscriptions/<sub>/resourceGroups/<rg>` | resource group |
| `/subscriptions/<sub>/resourceGroups/<rg>/providers/…` | resource |

Callers get one input instead of four mutually exclusive ones, and the shape is checked by a variable
validation. The `scope_kind` output still reports which of the four a scope resolved to, for callers
that branch on it.

**Changing `scope` still destroys and recreates**, even though the Terraform address no longer moves:
`parent_id` forces replacement, and it has to — a policy assignment at a subscription and the same
assignment at a resource group are different ARM resources with different IDs. Moving one between
scopes is not an in-place update.

### Managed identities

When a managed identity is enabled on an assignment, `identity_role_assignments` grants the
system-assigned identity the roles a `DeployIfNotExists` or `Modify` policy needs — at the assignment
scope by default, or at any scope you name. That second case matters when the policy remediates into a
different resource group or subscription than the one it is assigned at.

## Manual connection approval

`azure-res-network-privateendpoint` covers the case the service-owning modules do not: an endpoint
whose target belongs to someone else. Where a module wraps its own private-linkable service —
`azure-res-cache-redis`, `azure-res-signalrservice-signalr` — its built-in `private_endpoints` input
stays the right tool, because it can reference the target resource directly.

ARM carries the connection in one of two mutually exclusive body properties, and `is_manual_connection`
picks which:

| | `privateLinkServiceConnections` | `manualPrivateLinkServiceConnections` |
|---|---|---|
| `is_manual_connection` | `false` (default) | `true` |
| Approved | on creation | out of band, by the target's owner |
| Needs | write access on the target | nothing — the request is queued |
| Extra input | — | optional `request_message`, capped at 140 chars by ARM |

Both arrays are always sent, one populated and one empty. An ARM write is a full replace, so omitting
the unused one would leave the previous connection in place when the flag is flipped.

**A `Pending` endpoint is a successful apply, not a failed one.** The endpoint exists and holds a
subnet address; no traffic crosses it until the owner approves, and no DNS records appear in a zone
group before then. Terraform has no part in the approval and does not wait for it — read the
`connection_status` output on a later refresh, and gate anything downstream on it rather than on apply
having succeeded.

Cross-tenant targets — MongoDB Atlas, Snowflake, Databricks — only offer the manual path. They also
tend to identify the connection by name on their side, so set `private_service_connection_name`
explicitly instead of taking the `<name>-psc` default. A Private Link Service target publishes no
group IDs, so leave `subresource_names` empty; it is the same reason
`az network private-endpoint create` takes no `--group-id` against one.

## Agent readiness

Run Command is delivered by the VM agent, and the write fails while that agent reports NOT READY — a
real hazard on a freshly created or just-restarted machine.
`azure-ptn-compute-virtualmachine-runcommand` handles this with azapi's `retry`, applied to both the
run command and the optional restart: the write itself is retried until it is accepted, which is
stronger than polling agent status and then racing what you learned, and it keeps the module free of
provisioners and runner-side tooling.

```hcl
retry = {
  error_message_regex = ["<the message from your failed apply>"]
  interval_seconds    = 10
}
```

Patterns are the caller's to supply. The message ARM returns for a not-ready agent varies by OS and
failure mode, so a pattern hardcoded in the module would be a guess — and a guess that matches nothing
is worse than none, because it looks like protection without being any. AVM's virtual machine module
exposes `retry` the same way and hardcodes nothing.

Retrying is bounded by the Terraform context deadline, not a retry count, so `timeouts.create` decides
how long a not-ready agent is tolerated.

Terraform cannot poll on response content in any case: azapi's `retry` matches *error* responses, and
an agent that is not ready yet is a `200` whose body simply says so. Retrying the real operation is the
only provider-native option.

## Aegis

Aegis is a repository-specific Azure Policy guardrail family, not an upstream Azure concept. Both
shield modules compose `azure-res-policy-definition`, `-set-definition` and `-assignment` into
deny-delete protection.

**`azure-ptn-policy-aegis-shield-tag-protection`** — turnkey. Anything carrying the tag
`aegis = deny-delete` is shielded from delete operations until the tag is removed. Two definitions are
generated: one in `Indexed` mode with `cascadeBehaviors.resourceGroup = "deny"` so a tagged child also
blocks delete on its parent resource group, and one in `All` mode for resource groups that carry the
tag themselves (Indexed mode does not evaluate resource groups).

> **The tag contract is fixed and not configurable.** The tag name (`aegis`), the trigger value
> (`deny-delete`), the case-insensitive match, the policy modes and the cascade behaviour are all part
> of the pattern. Consumers key off them. Only the effect (`DenyAction` / `Disabled`), the assignment
> scope, and the usual behaviour knobs are inputs. Read the banner in `main.tf` before touching any of
> it.

**`azure-ptn-policy-aegis-shield-protection`** — explicit. Targets resources by ARM ID, one assignment
per protected resource. Use it when tagging is impractical, or when protection must exist *before* the
resource does — tag-based policies only evaluate tags that already exist.

## Managed instance SKU names

`azure-res-sql-managedinstance` sends the body straight through and compares what ARM
returns, so `sku_name` must be spelled the way the ARM catalogue spells it:

| tier | family | `sku_name` |
|---|---|---|
| GeneralPurpose | Gen5 | `GP_Gen5` |
| GeneralPurpose | Gen8IH | `GP_G8IH` |
| GeneralPurpose | Gen8IM | `GP_G8IM` |
| BusinessCritical | Gen5 | `BC_Gen5` |
| BusinessCritical | Gen8IH | `BC_G8IH` |
| BusinessCritical | Gen8IM | `BC_G8IM` |

The premium-series names drop the `en`. A configuration carrying azurerm's `BC_Gen8IH`
is not an ARM SKU name — the provider used to translate it, and nothing translates it
here, so it diffs on every plan forever. The Gen5 names are unchanged.

Two neighbouring properties normalise the same way, and are the other two worth
checking when porting a leaf off the azurerm module:

- `backup_storage_redundancy` takes ARM's `Geo` / `GeoZone` / `Local` / `Zone`. An
  azurerm `GZRS` is `GeoZone` here.
- `proxy_override` must name the value ARM resolves *to*. Configuring `Default`
  returns `Redirect`, and the config then never matches the response.

A validation rejects an unknown SKU name, and a precondition rejects a vCore count the
family does not offer — both list what is valid. The vCore lists were measured against
`Microsoft.Sql/locations/<region>/capabilities` in northeurope and westeurope, which
returned identical values; what varies by region is whether a family is offered at
all, which only ARM can answer.

## Fabric capacity administrators

`Microsoft.Fabric/capacities` stores `properties.administration.members` as an unordered
set. It neither preserves the order it is sent nor returns a stable one a caller could
reproduce, so any module that compares that path against the response diffs on every
plan, forever — the apply succeeds, ARM keeps its own order, and the next refresh renders
the same reorder.

This was measured against two live capacities in different subscriptions. A PATCH
carrying the members sorted left ARM's ordering untouched in both, and the follow-up plan
was identical to the one before the apply. Sorting the list first — what
[`Azure/avm-res-fabric-capacity/azure`](https://registry.terraform.io/modules/Azure/avm-res-fabric-capacity/azure/latest)
0.1.0 does — does not avoid this; it is what makes it certain, because ARM's order is
never alphabetical.

`azure-res-fabric-capacity` therefore excludes the path from body comparison with
`ignore_body_changes` and gives membership its own owner, an `azapi_resource_action`
holding a PATCH. An action's body comes from configuration and is never refreshed against
ARM, which is what makes it order-stable where the resource's own body is not: it re-runs
when the member set changes and stays quiet when it does not.

Two consequences worth knowing:

- **Membership is reconciled on apply, not detected on plan.** A member added to the
  capacity out of band — through the Fabric portal, say — is not surfaced as drift. The
  next apply that changes the set overwrites it, because the PATCH sends the configured
  set whole.
- **`administration_members` is not the same thing as `role_assignments`.** The first
  governs who administers the capacity inside Fabric; the second is ARM control-plane
  RBAC. Granting one does not grant the other.

`azapi_resource_action` is not created, updated or deleted the way a resource is — removing
the module's members from configuration does not remove them from the capacity, because
there is no PATCH left to send. Set the desired final set instead.

## Submodule: agentpool

A managed cluster carries its pools in `properties.agentPoolProfiles`, and ARM also exposes each
one as a child resource. Both are real, and the split between them is forced rather than chosen.

ARM will not create a cluster with an empty profile list, so one system pool has to be in the
create body — that is the parent module's `default_node_pool`. But an ARM write is a full replace,
so a later PUT carrying only that pool would strip every other one. The cluster therefore ignores
drift on `agentPoolProfiles` entirely, and `modules/agentpool` owns every additional pool as
`Microsoft.ContainerService/managedClusters/agentPools`.

Two consequences:

- **The system pool is not manageable through the submodule**, and the pools that are do not appear
  in the cluster's plan. They are separate resources with separate lifecycles.
- **`count` is sent only when the autoscaler is off.** With it on, the property is omitted rather
  than ignored — `ignore_null_property` drops the null, so the running size is neither written nor
  compared and a scaled-out pool is never dragged back. That leaves `node_count` reconcilable in
  the mode where it means something, instead of inert in both.

Every pool `locks` the cluster. AKS runs one operation per cluster at a time and fails the rest with
a conflict, so a `for_each` over pools — which Terraform would otherwise apply in parallel — fails
on all but the first without it.

### Replacing a pool without a capacity gap

`vm_size` is immutable, so changing it replaces the pool — by default destroying it first, which
takes that capacity to zero until the replacement finishes. `create_before_destroy` inverts the
order, at the cost of the pool's name: ARM will not hold two pools of the same name on one cluster,
so the replacement is created as `<name>` plus a four-character suffix and that generated name is
then held fixed.

Because `create_before_destroy` cannot be set from a variable, the pool is declared twice and the
two are mutually exclusive on `count`. They share one body. The generated name has to be ignored —
`uuid()` is re-evaluated every plan — which is why a `terraform_data` keeper carries the logical
name and makes a change to `name` a replacement again.

Two things this costs, both checked by a validation rather than left to fail at apply: the name in
`kubectl get nodes` is not the `name` input, and the suffix eats four of the twelve characters a
pool name is allowed. A Windows pool is capped at six, so there is no room at all and the option is
rejected there.

## Submodule: bgp-connection

[`azure-res-network-routeserver/modules/bgp-connection`](../../src/modules/azure-res-network-routeserver/modules/bgp-connection/)
creates one BGP peering between an existing route server and an NVA.

It is a submodule rather than an input on the route server because the two have different owners
in practice: the hub network owns the route server, while the configuration that deploys an NVA is
the one that knows its address and ASN. Creating the connection only lets the route server accept
the session — the NVA still peers with both of the parent's `virtual_router_ips`.

A `ReadOnly` lock on the route server blocks writes to its children, this one included.

## Submodule: elastic-pool and database

[`azure-res-sql-server/modules/elastic-pool`](../../src/modules/azure-res-sql-server/modules/elastic-pool/)
and
[`azure-res-sql-server/modules/database`](../../src/modules/azure-res-sql-server/modules/database/)

Both take the server's ARM resource ID as `parent_id`, so either can be managed by a
configuration that does not own the server. A database takes an `elastic_pool_resource_id`
to join a pool, and then must leave `sku` null - the pool supplies the tier, and ARM
rejects a SKU alongside a pool. A standalone database requires one. Preconditions catch
each direction.

`max_size_gb` is **not** governed by the pool and applies inside one. Every pooled
database carries its own `maxSizeBytes` — a per-database cap drawn from the pool's
shared storage — and ARM accepts it. Leaving it null means "whatever the tier
defaults to", not "inherit the pool".

Sizes are in GB and converted to the bytes ARM wants. The factor is 1024^3, because
Azure says "GB" and means GiB - `100` sends `107374182400`.

### Backup retention is the reason to manage a database here

Both retention policies are separate ARM child resources and are easy to leave
unmanaged. The consequence is asymmetric:

| Policy | Survives dropping the database | Survives deleting the SERVER |
|---|---|---|
| `short_term_retention` (PITR) | yes, within the window | **no** |
| `long_term_retention` (LTR) | yes | **yes**, restorable to another server |

Deleting a logical server deletes its databases and their PITR backups together, and
neither can be recovered. LTR is the only class that outlives the server, and an
unconfigured policy reads back as `PT0S` on every field - indistinguishable from having
none. `week_of_year` is required whenever `yearly_retention` is set, or ARM keeps no
yearly backup at all.

## Submodule: vnet-link

[`azure-res-network-privatednszone/modules/vnet-link`](../../src/modules/azure-res-network-privatednszone/modules/vnet-link/)
creates one virtual network link on an existing private DNS zone.

Choose between it and the collection pattern by ownership, not by count:

| Use | When |
|---|---|
| `modules/vnet-link` | One link, managed as its own unit — typically the zone and the link are owned by different configurations |
| `azure-ptn-network-privatednszone-vnet-links` | Many links driven from one map, owned together |

Nothing in this repository sources `vnet-link`, and that means nothing — submodule paths are
addressable by git ref, so external consumers reach it directly.

## Migrating to AzAPI

Every module in this family moved from `hashicorp/azurerm` to `Azure/azapi`. Inputs and outputs kept
their shape, so caller configuration does not move — but the resource *types* changed, and `moved`
blocks cannot cross a type change. Terraform reads the new addresses as unrelated resources and plans a
destroy-and-recreate. Adopt the existing resources into the new addresses instead. Per-module recipes
live in each module's README; the shape is the same everywhere:

```bash
terraform state pull > backup.tfstate
terraform state rm '<old address>'
terraform import '<new azapi address>' '<ARM resource ID>'
terraform plan   # expect: No changes
```

Take the backup. `state rm` is not reversible without it, and a half-migrated unit is worse than an
unmigrated one.

Six things that are easy to get wrong:

- **`azapi_update_resource` cannot be imported at all.** `terraform import` answers
  *"Resource Import Not Implemented"*. Modules use it for the ARM singletons the service
  materialises alongside their parent, so those addresses have to be left to *create* —
  each one is a PATCH, and against an already-correct child it writes nothing. A
  post-migration plan reading `N to add` is expected there, not a failed import.

- **Role assignments** must have their `random_uuid` imported with the *existing* assignment GUID, or a
  fresh UUID is generated and the assignment is replaced — a brief loss of access on apply. Supplying
  `role_assignments[*].name` explicitly does the same job from configuration.
- **A resource with no role assignments** lands on an outputs-only plan rather than *no changes*:
  `import` persists an empty `for_each` output as null instead of `{}`. The settling apply reports
  `0 added, 0 changed, 0 destroyed`.
- **`import` records the provider's newest API version, not the one in the module.** The first plan
  afterwards can show an in-place change that only rewrites `type` to the pinned version. It is a state
  correction, not an Azure write.
- **Some import IDs need `?api-version=<version>` appended.** Policy assignments and exemptions report
  *"Cannot import non-existent remote object"* without it, even though the ID is correct.
- **Record-set tags live in `properties.metadata`**, not resource `tags`. AzAPI does not paper over
  that the way the azurerm provider did.

A plan that still shows a destroy means an import did not land. Do not apply it.

### What the move fixed

Scope handling collapsed. `azure-res-policy-assignment` and `azure-res-policy-exemption` each replaced
four scope-specific resource types with one; `azure-res-policy-set-definition` replaced a pair that
could not `moved` between them at all. Anchoring is now `parent_id`, so re-anchoring an initiative
between a management group and a subscription no longer needs state surgery.

⚠️ It is still a destroy-and-recreate, and for a deny-effect initiative that gap is real: every
assignment referencing the initiative is **unenforced for the length of the apply**. The resource comes
back identical, so schedule the change deliberately rather than letting it ride along with an unrelated
one.
