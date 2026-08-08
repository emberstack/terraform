# Azure

Modules on the `hashicorp/azurerm` provider, except the private-DNS-zone family — the zone module, its
`vnet-link` submodule, and both `privatednszone` pattern modules are on `Azure/azapi`. The rest are
being moved the same way; each carries a migration section when it moves, because the resource type
changes and `moved` blocks cannot cross that.

Input shapes mirror [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/) where an
AVM equivalent exists — `name`, `resource_group_name`, `tags`, `role_assignments` — and add what AVM
lacks. Keep new inputs shaped the AVM way.

## Resource modules

| Module | What it manages |
|---|---|
| [`azure-res-authorization-roledefinition`](../../src/modules/azure-res-authorization-roledefinition/) | Custom RBAC role definition |
| [`azure-res-cache-redis`](../../src/modules/azure-res-cache-redis/) | Managed Redis, with private endpoint, diagnostic settings, management lock and role assignments |
| [`azure-res-network-dnszone`](../../src/modules/azure-res-network-dnszone/) | Public DNS zone and role assignments, optionally writing the delegation NS record into a parent zone |
| [`azure-res-network-privatednszone`](../../src/modules/azure-res-network-privatednszone/) | Private DNS zone and role assignments (+ [`modules/vnet-link`](#submodule-vnet-link)) |
| [`azure-res-policy-assignment`](../../src/modules/azure-res-policy-assignment/) | Policy or initiative assignment, [scope-routed](#scope-routing) |
| [`azure-res-policy-definition`](../../src/modules/azure-res-policy-definition/) | Policy definition |
| [`azure-res-policy-exemption`](../../src/modules/azure-res-policy-exemption/) | Policy exemption, [scope-routed](#scope-routing) |
| [`azure-res-policy-set-definition`](../../src/modules/azure-res-policy-set-definition/) | Policy initiative |
| [`azure-res-signalrservice-signalr`](../../src/modules/azure-res-signalrservice-signalr/) | SignalR service, with network ACL, private endpoint, diagnostic settings, lock and role assignments |

## Pattern modules

| Module | What it does |
|---|---|
| [`azure-ptn-authorization-roledefinition-collection`](../../src/modules/azure-ptn-authorization-roledefinition-collection/) | Many role definitions from one map |
| [`azure-ptn-network-dnszone-records`](../../src/modules/azure-ptn-network-dnszone-records/) | A, AAAA, CAA, CNAME, MX, NS, PTR, SRV and TXT records in an existing public zone |
| [`azure-ptn-network-privatednszone-records`](../../src/modules/azure-ptn-network-privatednszone-records/) | A, AAAA, CNAME, MX, PTR, SRV and TXT records in an existing private zone |
| [`azure-ptn-network-privatednszone-vnet-links`](../../src/modules/azure-ptn-network-privatednszone-vnet-links/) | Virtual network links across many zones |
| [`azure-ptn-network-virtualnetwork-dnsservers`](../../src/modules/azure-ptn-network-virtualnetwork-dnsservers/) | DNS server list on an existing virtual network |
| [`azure-ptn-policy-aegis-shield-protection`](../../src/modules/azure-ptn-policy-aegis-shield-protection/) | [Aegis](#aegis) deny-delete by explicit resource ID |
| [`azure-ptn-policy-aegis-shield-tag-protection`](../../src/modules/azure-ptn-policy-aegis-shield-tag-protection/) | [Aegis](#aegis) tag-driven deny-delete |
| [`azure-ptn-policy-exemption-collection`](../../src/modules/azure-ptn-policy-exemption-collection/) | Many policy exemptions from one map |

## Scope routing

`azure-res-policy-assignment` and `azure-res-policy-exemption` accept a single `scope` string and pick
the matching resource type from its shape:

| `scope` looks like | Resource used |
|---|---|
| `/providers/Microsoft.Management/managementGroups/<mg>` | management group |
| `/subscriptions/<sub>` | subscription |
| `/subscriptions/<sub>/resourceGroups/<rg>` | resource group |
| `/subscriptions/<sub>/resourceGroups/<rg>/providers/…` | resource |

Callers get one input instead of four mutually exclusive ones, and the four underlying resources are
pulled through `coalesce` so outputs are uniform regardless of scope.

**Changing `scope` across kinds changes the resource address** and therefore destroys and recreates
the assignment. Moving a policy assignment between a subscription and a resource group is not an
in-place update.

### Managed identities

When a managed identity is enabled on an assignment, `identity_role_assignments` grants the
system-assigned identity the roles a `DeployIfNotExists` or `Modify` policy needs — at the assignment
scope by default, or at any scope you name. That second case matters when the policy remediates into a
different resource group or subscription than the one it is assigned at.

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

## Migrating a management-group-scoped initiative

`azure-res-policy-set-definition` picks its resource type from the scope: `management_group_id` set
gives `azurerm_management_group_policy_set_definition`, null gives `azurerm_policy_set_definition`.
The split exists because `management_group_id` on the latter is deprecated and removed in azurerm
v5.0. Both types carry identical schemas, so no input or output changes shape.

Changing scope type changes the Terraform address. The two types address the same ARM resource ID,
but azurerm does not implement `MoveState` for the pair — a `moved` block fails with *"Move Resource
State Not Supported"* — so the module deliberately ships none.

**By default the initiative is destroyed and recreated**, along with every assignment referencing it.
The resource itself comes back identical, but the assignment is **unenforced for the length of the
apply**. For a deny-effect initiative that is a real gap: schedule it, and do not run it as a
side effect of an unrelated change.

If you cannot accept that gap, re-address the state instead. Because the ARM resource ID is
unchanged, this is a state-only operation and the plan afterwards is empty. Take a state backup
first, then:

```bash
terraform state rm 'module.<path>.azurerm_policy_set_definition.this'
```

```bash
terraform import 'module.<path>.azurerm_management_group_policy_set_definition.management_group[0]' '/providers/Microsoft.Management/managementGroups/<mg>/providers/Microsoft.Authorization/policySetDefinitions/<name>'
```

Then plan. A correct migration reports **no changes** — nothing is created or destroyed in Azure.
A plan that still shows a destroy means the import did not land; do not apply it.

The azurerm major cap stays in place for now. This module no longer blocks it, but the other
azurerm modules have not been checked against v5.

## Migrating the private-DNS-zone family to AzAPI

The zone module, `modules/vnet-link`, and both `privatednszone` pattern modules moved from `azurerm`
to `Azure/azapi`. Inputs and outputs are unchanged; the resource *types* are not, so `moved` blocks do
not apply — Terraform reads the new addresses as unrelated resources and plans a destroy-and-recreate.
Adopt them instead. Per-module recipes are in
[`azure-res-network-privatednszone`'s README](../../src/modules/azure-res-network-privatednszone/README.md);
the shape is the same everywhere:

```bash
terraform state pull > backup.tfstate
terraform state rm '<old azurerm address>'
terraform import '<new azapi address>' '<ARM resource ID>'
terraform plan   # expect: No changes
```

Three things that are easy to get wrong:

- **Role assignments** on the zone module must have their `random_uuid` imported with the *existing*
  assignment GUID, or a fresh UUID is generated and the assignment is replaced — a brief loss of access
  on apply.
- **A zone with no role assignments** lands on an outputs-only plan rather than *no changes*: `import`
  persists an empty `for_each` output as null instead of `{}`. The settling apply reports
  `0 added, 0 changed, 0 destroyed`.
- **Record-set tags live in `properties.metadata`**, not resource `tags`. AzAPI does not paper over
  that the way the azurerm provider did.

A plan that still shows a destroy means an import did not land. Do not apply it.
