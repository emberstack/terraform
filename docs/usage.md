# Usage

## Consuming a module

Modules are consumed by git source ref. There is no registry publication.

```hcl
module "example" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/<module-name>?ref=vX.Y.Z"

  # module inputs
}
```

Nested submodules are addressable exactly the same way — the `//` path just goes deeper:

```hcl
module "vnet_link" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-privatednszone/modules/vnet-link?ref=vX.Y.Z"
}
```

## Pinning

**Pin `ref` to a tag.** Every module change merged to `main` publishes a semver tag and a GitHub
Release — see [Releases](contributing.md#releases) — so tags are immutable and carry generated notes.

Tracking a branch means an unannounced change reaches you on your next `terraform init`, with no
version gate and no staged rollout.

```hcl
# Good — immutable, and the release notes tell you what changed
?ref=vX.Y.Z

# Also immutable, but no notes and no ordering
?ref=1a2b3c4d5e6f7890abcdef1234567890abcdef12

# Risky — moves under you
?ref=main
```

Examples throughout the documentation write `vX.Y.Z`. Substitute the release you are adopting — the
[releases page](https://github.com/emberstack/terraform/releases) lists them newest first.

## Providers are the caller's responsibility

Modules declare `required_providers` in `versions.tf` and **never contain a `provider` block**. The
consuming configuration authenticates and configures the provider:

```hcl
provider "azapi" {
  subscription_id = var.subscription_id
}

module "private_dns_zone" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-privatednszone?ref=vX.Y.Z"

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
  source    = "git::https://github.com/emberstack/terraform.git//src/modules/fortios-res-fortigate-firewall-policy?ref=vX.Y.Z"
  providers = { fortios = fortios.site_a }

  # ...
}
```

## Version requirements

**Each module's `versions.tf` is authoritative** — read it rather than a table here, which would be
one more thing to bump.

Every provider constraint carries an upper bound below the next major, so a major release cannot
reach you unannounced. Floors are the newest published version at the time of writing, so a fresh
`init` normally resolves to the floor exactly. `required_version` is uniform across the tree.

## Lock files

`.terraform.lock.hcl` is **not** committed, on purpose. Lock files inside reusable modules cause
cross-platform checksum mismatches for consumers. Your configuration keeps its own lock file — that
is the correct place for it.

## Upgrading

1. Read the diff between your pinned tag and the target tag for the module path you consume. The
   release notes on the intervening tags summarise what landed. **A break can land in a minor or a
   patch** — majors here are cut deliberately, not inferred — so read the notes rather than the
   number: anything breaking is listed under *Breaking Changes*.
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
