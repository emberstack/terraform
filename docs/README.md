# Documentation

Reference material for `emberstack/terraform` — a library of reusable, independently-versioned
Terraform modules for Azure, Entra ID, FortiGate and GitHub.

| Guide | Read it when |
|---|---|
| [Usage](usage.md) | You want to consume a module from your own configuration |
| [Conventions](conventions.md) | You want to know how modules are named, laid out and styled |
| [Contributing](contributing.md) | You want to add or change a module |

## Module reference

Each family guide explains how that provider family behaves — the patterns it follows, the quirks it
works around — and lists every module in it.

| Family | Provider |
|---|---|
| [Azure](modules/azure.md) | `Azure/azapi` |
| [Entra ID](modules/entra.md) | `hashicorp/azuread` |
| [FortiGate](modules/fortios.md) | `fortinetdev/fortios` |
| [GitHub](modules/github.md) | `integrations/github` |

Nested submodules are documented alongside their parents.

## What these docs deliberately leave out

**Input and output tables are not reproduced here.** Every variable and output in the repository
carries a `description`, so `variables.tf` and `outputs.tf` already are the reference — and they
cannot drift from the code, because they *are* the code. Generated per-module pages would need a
generator and a CI check to keep them honest; `check-docs.py` verifies that every variable and output
*has* a description, not that a copy of it elsewhere still matches.

These docs cover what the code cannot state on its own: conventions, provider quirks, composition
patterns, and the reasoning behind decisions that look strange from the outside. For *"what inputs
does this module take"*, read the module.
