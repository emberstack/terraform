# Usage

## Consuming a module

Modules are consumed by git source ref. There is no registry publication.

```hcl
module "example" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/<module-name>?ref=<ref>"

  # module inputs
}
```

Nested submodules are addressable exactly the same way — the `//` path just goes deeper:

```hcl
module "vnet_link" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-privatednszone/modules/vnet-link?ref=v0.1.0"
}
```

## Pinning

**Pin `ref` to a tag.** Every push to `main` publishes a semver tag and a GitHub Release —
see [Releases](contributing.md#releases) — so tags are immutable and carry generated notes.

Tracking a branch means an unannounced change reaches you on your next `terraform init`, with no
version gate and no staged rollout.

```hcl
# Good — immutable, and the release notes tell you what changed
?ref=v0.1.0

# Also immutable, but no notes and no ordering
?ref=1a2b3c4d5e6f7890abcdef1234567890abcdef12

# Risky — moves under you
?ref=main
```

`v0.1.0` is the first release. Module READMEs pin to it; bump as you adopt later versions.

## Providers are the caller's responsibility

Modules declare `required_providers` in `versions.tf` and **never contain a `provider` block**. The
consuming configuration authenticates and configures the provider:

```hcl
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

module "private_dns_zone" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-privatednszone?ref=v0.1.0"

  name                = "privatelink.blob.core.windows.net"
  resource_group_name = "rg-example"
}
```

This is deliberate: it keeps modules usable with provider aliases, multiple subscriptions, or several
target devices from one configuration.

### Multiple provider instances

Pass aliased providers explicitly. FortiGate modules are the common case — one configuration managing
several appliances:

```hcl
provider "fortios" {
  alias    = "site_a"
  hostname = var.site_a_hostname
  token    = var.site_a_token
}

module "site_a_policy" {
  source    = "git::https://github.com/emberstack/terraform.git//src/modules/fortios-res-fortigate-firewall-policy?ref=v0.1.0"
  providers = { fortios = fortios.site_a }

  # ...
}
```

## Version requirements

| | Constraint |
|---|---|
| Terraform | `>= 1.15` |
| `hashicorp/azurerm` | `>= 4.81, < 5.0` |
| `hashicorp/azuread` | `>= 3.9, < 4.0` |
| `integrations/github` | `>= 6.13, < 7.0` |
| `fortinetdev/fortios` | `>= 1.25, < 2.0` |
| `magodo/restful` | `>= 0.25.2, < 1.0` |
| `hashicorp/random` | `>= 3.9, < 4.0` |

Every constraint carries an upper bound below the next major, so a provider major release cannot
reach you unannounced. Floors are set to the newest published version at the time of writing, which
means a fresh `init` normally resolves to the floor exactly.

`required_version = ">= 1.15"` is uniform across all 74 module directories.

### Why azurerm is capped below 5.0

`azure-res-policy-set-definition` uses `management_group_id` on `azurerm_policy_set_definition`, which
azurerm v5.0 removes. Migrating means switching resource types, which changes the resource address and
would destroy and recreate live policy set definitions. The cap is load-bearing until that migration
lands with `moved` blocks. See [Contributing](contributing.md#known-deferred-work).

## Lock files

`.terraform.lock.hcl` is **not** committed, on purpose. Lock files inside reusable modules cause
cross-platform checksum mismatches for consumers. Your configuration keeps its own lock file — that
is the correct place for it.

## Upgrading

1. Read the diff between your pinned tag and the target tag for the module path you consume. The
   release notes on the intervening tags summarise what landed; a major tag means a break was
   marked, so read that one closely.
2. `terraform plan` before merging. Modules aim for additive change with defaults, but plan output is
   the only reliable answer.
3. Bump one module at a time when several are pinned to the same ref — it keeps the blame surface
   small when a plan surprises you.

## State considerations

Two things end up in state that are worth knowing about before you consume them:

- **GitHub Actions secrets** (`github-res-*` modules) are submitted as plaintext and are therefore
  persisted in your state file. GitHub never returns them, so out-of-band changes are not detected.
  Protect the state backend accordingly.
- **Generated wireless pre-shared keys** (`fortios-res-fortigate-wirelesscontroller-vap`) use
  `random_password`, whose value lives in state by design.

## Related

- [Conventions](conventions.md) — how to read a module name and find your way around one
- [Contributing](contributing.md) — local validation loop, adding a module
