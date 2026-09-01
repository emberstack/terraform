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
| [`azure-res-kubernetesconfiguration-extension`](../../src/modules/azure-res-kubernetesconfiguration-extension/) | Cluster extension on AKS, Arc or AKS hybrid, with management lock and role assignments for the extension's identity |
| [`azure-res-network-dnszone`](../../src/modules/azure-res-network-dnszone/) | Public DNS zone and role assignments, optionally writing the delegation NS record into a parent zone |
| [`azure-res-network-privatednszone`](../../src/modules/azure-res-network-privatednszone/) | Private DNS zone and role assignments (+ [`modules/vnet-link`](#submodule-vnet-link)) |
| [`azure-res-network-privateendpoint`](../../src/modules/azure-res-network-privateendpoint/) | Standalone private endpoint against a target owned elsewhere, [automatic or manual](#manual-connection-approval), with DNS zone group, management lock and role assignments |
| [`azure-res-policy-assignment`](../../src/modules/azure-res-policy-assignment/) | Policy or initiative assignment, [scope-routed](#scope-routing) |
| [`azure-res-policy-definition`](../../src/modules/azure-res-policy-definition/) | Policy definition |
| [`azure-res-policy-exemption`](../../src/modules/azure-res-policy-exemption/) | Policy exemption, [scope-routed](#scope-routing) |
| [`azure-res-policy-set-definition`](../../src/modules/azure-res-policy-set-definition/) | Policy initiative |
| [`azure-res-signalrservice-signalr`](../../src/modules/azure-res-signalrservice-signalr/) | SignalR service, with network ACL, private endpoint, diagnostic settings, lock and role assignments |

## Pattern modules

| Module | What it does |
|---|---|
| [`azure-ptn-authorization-roledefinition-collection`](../../src/modules/azure-ptn-authorization-roledefinition-collection/) | Many role definitions from one map |
| [`azure-ptn-compute-virtualmachine-windows-fqdn`](../../src/modules/azure-ptn-compute-virtualmachine-windows-fqdn/) | Windows VM in-guest primary DNS suffix, written by a managed run command (so the guest FQDN matches its public DNS name) and applied by an ARM restart the apply blocks on until the VM is running again |
| [`azure-ptn-network-dnszone-records`](../../src/modules/azure-ptn-network-dnszone-records/) | A, AAAA, CAA, CNAME, MX, NS, PTR, SRV and TXT records in an existing public zone |
| [`azure-ptn-network-privatednszone-records`](../../src/modules/azure-ptn-network-privatednszone-records/) | A, AAAA, CNAME, MX, PTR, SRV and TXT records in an existing private zone |
| [`azure-ptn-network-privatednszone-vnet-links`](../../src/modules/azure-ptn-network-privatednszone-vnet-links/) | Virtual network links across many zones |
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

Five things that are easy to get wrong:

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
