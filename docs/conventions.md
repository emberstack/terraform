# Conventions

## Naming

Directory names follow AVM-style `<provider>-<kind>-<service>-<resource>`:

```
azure-res-network-privatednszone
│     │   │       └── resource
│     │   └────────── service
│     └────────────── kind
└──────────────────── provider
```

| Segment | Values |
|---|---|
| provider | `azure` (azurerm), `entra` (azuread), `fortios` (FortiGate), `github` |
| kind | `res`, `ptn`, `utl` |

### Kinds

- **`res` — resource module.** Wraps a single logical resource plus its tightly-coupled children.
  One deployable thing. `azure-res-cache-redis` is a Redis instance *and* its private endpoint,
  diagnostic settings, lock and role assignments — all meaningless without the instance.
- **`ptn` — pattern module.** Composes or fans out, usually `for_each` over a map input. Names
  commonly end `-collection`, `-records`, `-memberships`.
- **`utl` — utility module.** Pure computation. No resources, no providers, no `required_providers`
  entries — just `locals` and `outputs`.

### The FortiGate platform segment

FortiGate modules carry an extra segment: `fortios-<kind>-fortigate-<service>-<resource>`. All 38
device-facing FortiGate modules use it. The one exception is `fortios-utl-network-cidr`, which is
pure arithmetic and touches no device.

### `ptn` does not imply delegation

Only 5 of the 19 pattern modules source a sibling `res` module. The other 14 declare provider
resources inline, deliberately — it keeps the pattern self-contained when it is copied into a
Terragrunt cache, at the cost of some duplication. `fortios-ptn-fortigate-router-static-collection`
inlines even though a sibling `res` module exists.

Don't "fix" an inlining pattern module into a delegating one without a reason beyond tidiness.

## Module anatomy

Every module directory contains these four files. They are never folded together:

| File | Contents |
|---|---|
| `main.tf` | resources, data sources, locals |
| `variables.tf` | inputs — one `variable` block each |
| `outputs.tf` | outputs, each with a `description` |
| `versions.tf` | `terraform { required_version, required_providers }` |

**Provider version constraints live only in `versions.tf`.** No `provider` blocks anywhere inside a
module — see [Usage](usage.md#providers-are-the-callers-responsibility).

Three optional additions sit alongside them:

- **`README.md`** — usage, Inputs, Outputs, Requirements, Notes. Coverage is currently 16 of 63
  modules, so don't assume one exists.
- **`examples/basic/`** — sources the parent with `source = "../../"` and *does* declare a `provider`
  block. Only `entra-ptn-group-collection` has one today; treat examples as encouraged rather than
  established.
- **`modules/<child>/`** — nested submodules, same four-file layout.

### Nested submodules

Used when a child resource must be manageable independently of its parent — for example
`entra-res-group/modules/member` lets membership be managed separately from the group, which matters
when the two are owned by different configurations.

Submodule paths are addressable by git ref exactly like top-level modules. **A submodule with no
in-repo caller is not dead code** — external consumers reach it directly. Never delete or re-address
one based on in-repo reference count.

There is one layout exception: `fortios-ptn-fortigate-switchcontroller-managedswitch-ports` puts its
child at `port/` rather than `modules/port/`. Match `modules/<child>/` in new code.

## Variable style

Collection inputs are **maps of objects keyed by a stable identifier**, using
`optional(<type>, <default>)` for non-required fields:

```hcl
variable "records" {
  description = "DNS A records, keyed by record name."
  type = map(object({
    ttl     = optional(number, 3600)
    records = list(string)
  }))
  default  = {}
  nullable = false
}
```

The map key is the `for_each` address *and* the output key. Pick stable keys — renaming one
re-addresses that resource, and removing one from the middle of a map does not disturb its
neighbours only because the key, not the position, is the address.

### Validation

Validation is heavy and expected: length bounds, enum `contains(...)`, and regex `can(regex(...))`
checks with clear `error_message`s.

Two things to watch:

- **Tautologies never fire.** `condition = alltrue([for v in values(x) : v.scope != null || true])` is
  always true. If a check needs a second variable, reference it directly — cross-variable validation
  has been legal since Terraform 1.9 and every module here pins `>= 1.15`.
- **Don't validate enums you cannot verify.** The `fortios` provider does not publish its accepted
  values in the schema for many attributes. A guessed `contains(...)` list rejects working
  configurations. Validate what you can prove.

### Known deviations

The `fortios` family and `github-res-repository` (plus its three submodules) historically shipped
without `description` or `validation`. Descriptions have since been closed across the whole tree —
every variable and output now has one. **Validation coverage is still uneven**: the azure and entra
modules validate heavily, fortios has very little. New code should follow the azure/entra standard,
and touching an offender is a chance to close the gap.

### UUID-vs-UPN auto-routing

A recurring Entra pattern: a `map(string)` accepts either an object ID (UUID) or a user principal
name, partitioned by regex, with UPNs resolved through an `azuread_user` data source at plan time.
It has a sharp edge — see [Entra ID](modules/entra.md#the-unknown-at-plan-time-edge). When mirroring
this input into a `ptn` wrapper, copy the `res` module's object shape field-for-field.

## Comments

Comments earn their place by explaining what the code cannot.

**Write one for:** why a `lifecycle` block exists, why an attribute is deliberately left unset, why
iteration order is forced, why a value is hardcoded rather than exposed, a provider bug being worked
around, an ordering dependency invisible in the graph.

**Don't write:** prose restating the declaration below it, parentheticals narrating the next line,
`# Required` above a variable with no default, or past-tense notes about code that no longer exists.

### Banners

```hcl
# =============================================================================
# TITLE IN CAPS
# =============================================================================
# Optional body — only when there is non-obvious behaviour to explain. When
# present, close it with a fourth rule.
# =============================================================================
```

A banner is **not** a mandatory file header — 35 of 74 module `main.tf` files carry one. Add a banner
when you have something non-obvious to say. A title-only rule is fine as a section marker in a long
multi-resource file; what makes a banner noise is a body that restates the resource type.

Box-drawing characters (`╔ ║ ╚`) are not used anywhere in the tree. Don't introduce them.

## Azure input shapes

Azure modules mirror AVM input shapes where an AVM equivalent exists — `name`,
`resource_group_name`, `tags`, `role_assignments` — then add what AVM lacks. Shape new inputs the AVM
way so a consumer migrating between the two isn't rewriting call sites.
