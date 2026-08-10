# emberstack/terraform

A library of reusable, independently-versioned Terraform modules for Azure, Entra ID, FortiGate and GitHub.

This is a **module library**, not a deployment repository. There is no root configuration, no state and no
environment composition here — modules are consumed from other repositories by git source ref.

## Usage

```hcl
module "example" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/<module-name>?ref=vX.Y.Z"

  # ...
}
```

> **Pinning:** pin `ref` to a semver tag, published automatically whenever a module change lands on `main`.
> Tracking `main` instead means an unannounced change lands on your next `terraform init`.

Modules declare `required_providers` but never configure a provider. The consuming configuration is
responsible for authenticating and configuring the provider.

## Naming convention

Directory names follow AVM-style `<provider>-<kind>-<service>-<resource>`:

| Segment | Values |
|---|---|
| provider | `azure` (azapi), `entra` (azuread), `fortios` (FortiGate), `github` |
| kind | `res`, `ptn`, `utl` |

- **`res`** — resource module. Wraps a single logical resource plus tightly-coupled children.
- **`ptn`** — pattern module. Composes or fans out, usually `for_each` over a map input.
- **`utl`** — utility module. Pure computation: no resources, no providers.

FortiGate modules carry an extra platform segment: `fortios-<kind>-fortigate-<service>-<resource>`.

## Modules

Each family guide lists every module in it and explains how that provider family behaves. Some
modules carry nested submodules, documented alongside their parent.

| Family | Provider | |
|---|---|---|
| Azure | `Azure/azapi` | [Guide](docs/modules/azure.md) |
| Entra ID | `hashicorp/azuread` | [Guide](docs/modules/entra.md) |
| FortiGate | `fortinetdev/fortios` | [Guide](docs/modules/fortios.md) |
| GitHub | `integrations/github` | [Guide](docs/modules/github.md) |

## Requirements

Terraform and provider constraints are declared per module in its `versions.tf`, which is the
authoritative source. All carry an upper bound below the next major, so a provider major release
cannot reach you unannounced — see [Usage](docs/usage.md#version-requirements).

## Repository layout

Every module directory contains four required files — `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` —
optionally alongside `README.md`, `examples/` and `modules/` for nested submodules.

`.terraform.lock.hcl` is deliberately **not** committed: lock files in reusable modules cause cross-platform
checksum mismatches. Consumers pin their own.

## Development

[`pipeline.yaml`](.github/workflows/pipeline.yaml) runs **discovery → build → gate → release** on every
push to `main` and every pull request against `main`: `fmt`, a documentation consistency check, and
`init` + `validate` across every module directory. Pushing a topic branch runs nothing until you open
the pull request. `release` runs on push to `main` only — merges are tagged and published
automatically, a `feat:` commit bumping the minor and anything else the patch. Majors are not
inferred from breaking changes — they are asked for with `+semver: major` or a bumped
`next-version`.

The same checks locally:

```bash
terraform fmt -recursive
python .github/scripts/check-docs.py
cd src/modules/<module-name> && terraform init -backend=false && terraform validate
```

## Documentation

| Guide | |
|---|---|
| [Usage](docs/usage.md) | Consuming a module: source refs, pinning, provider wiring, upgrades |
| [Conventions](docs/conventions.md) | Naming, module anatomy, variable and comment style |
| [Contributing](docs/contributing.md) | Local validation loop, adding a module, deferred work |

Per-module inputs and outputs are not duplicated in the docs — every variable and output carries a
`description`, so `variables.tf` and `outputs.tf` are the reference.

## License

[MIT](LICENSE)
