# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

**Reference documentation lives in [`docs/`](docs/).** This file does not duplicate it — it carries the
rules that decide whether a change is safe, and points at the docs for everything descriptive. When
you need the detail, read the doc; when you change a convention, update the doc.

| Looking for | Read |
|---|---|
| Naming, module anatomy, variable and comment style | [docs/conventions.md](docs/conventions.md) |
| Validation loop, adding a module, deferred work | [docs/contributing.md](docs/contributing.md) |
| Source refs, pinning, provider wiring, version matrix | [docs/usage.md](docs/usage.md) |
| Per-family behaviour and quirks | [docs/modules/](docs/modules/) — [azure](docs/modules/azure.md), [entra](docs/modules/entra.md), [fortios](docs/modules/fortios.md), [github](docs/modules/github.md) |

## What this repository is

A **library of reusable, independently-versioned Terraform modules** — not a deployment repo. No root
configuration, no state, no environment composition. Modules are consumed by *other* repos via a git
source ref.

Every module lives under `src/modules/<module-name>/` and stands on its own: **63** modules plus 11
nested submodules — **74 module directories** to sweep. Per-family counts live in
[docs/README.md](docs/README.md#module-reference).

## Working here

CI is [`.github/workflows/pipeline.yaml`](.github/workflows/pipeline.yaml), four jobs:
**discovery → build → gate → release**. `discovery` resolves the version, `build` runs `fmt` + the docs
check + `validate`, `gate` is the single required status check, and `release` tags and publishes.
`build` is skipped entirely when a change touches neither `src/` nor the docs; any change under `src/`
validates the whole tree. Every merge that touches `src/` is released — **`feat:` bumps the minor and
anything else the patch. A major is never inferred: ask for it with `+semver: major` or a bumped
`next-version`.** Docs- and CI-only merges do not publish.
([details](docs/contributing.md#what-ci-runs))

Run the same checks locally before pushing:

```powershell
terraform fmt -recursive                                    # from repo root
python .github/scripts/check-docs.py
cd src/modules/<module-name>
terraform init -backend=false && terraform validate
```

- `validate` needs `init` first to resolve providers and relative submodule sources.
- Sweeping the tree: set `TF_PLUGIN_CACHE_DIR` first or you download providers 75 times. (75, not
  74 — the sweep also inits the one `examples/basic/`, which the module count excludes.)
  Script in [contributing.md](docs/contributing.md#sweep-the-whole-tree).
- **An `init` failure after a version bump is usually a stale local `.terraform.lock.hcl`, not a repo
  defect.** Re-run with `-upgrade`. Do not "fix" `versions.tf` to satisfy a stale lock.
  ([why](docs/contributing.md#the-stale-lock-trap))

## Rules that override convenience

These are the ones that cause real damage when ignored. Each links to the reasoning.

1. **Every merge that touches `src/` is a release.** Trunk-based: there is one long-lived branch,
   and merging a module change to it tags a version and publishes it. Docs, CI and repository config
   do not publish — a consumer resolves `//src/modules/<name>`, so nothing outside `src/` reaches
   them. The commit subject picks the segment — `feat:` a minor,
   anything else a patch. Verify a module's interface and behaviour before changing either, and
   prefer additive changes with defaults. A breaking change is not forbidden, but it does **not**
   bump the major on its own: mark it `<type>!:` or with a `BREAKING CHANGE:` footer so the release
   notes say so, and let breaks accumulate until a major is cut deliberately. Because the version
   no longer carries that signal, an unmarked break is invisible — the notes are the only place a
   consumer reads it.
2. **Never delete or re-address a module based on in-repo reference count.** Submodule paths are
   addressable by git ref, so external callers reach them directly.
   `azure-res-network-privatednszone/modules/vnet-link` reads as dead code and is not.
   ([why](docs/conventions.md#nested-submodules))
3. **Do not fix the deferred items in passing.** They were reviewed and postponed because the fix is
   riskier than the defect — resource-address changes, live-device writes, values callers already
   consume. They need a version tag and consumer coordination.
   ([the list](docs/contributing.md#known-deferred-work))
4. **Keep consumer identifiers out.** Public repo: no customer names, real hostnames, switch or SSID
   names, domains, serials, directory object IDs, or downstream filesystem paths. Use `example.com`,
   `core-sw-01`, `corp-nac`, `rg-example`.
5. **Never commit `.terraform.lock.hcl`.** Gitignored on purpose — lock files in reusable modules
   cause cross-platform checksum mismatches. Consumers pin their own. Same for state and tfvars.
6. **No `provider` blocks inside modules.** `required_providers` in `versions.tf`; the consumer
   configures and authenticates. (The one exception in the tree is under `examples/`.)
7. **Every provider constraint keeps an upper bound below the next major.**
   ([matrix](docs/usage.md#version-requirements))
8. **`GitVersion.yaml` and `cliff.toml` diverge on purpose — keep the anchoring identical.**
   `cliff.toml` flags all three breaking markers (`<type>!:`, a `BREAKING CHANGE:` footer,
   `+semver: major`) in the notes; GitVersion majors on the last one only. That gap is the design.
   What must not drift is the `(?m)` anchoring: a marker on a body line has to behave the same in
   both, or the notes and the number describe different commits.
   ([why](docs/contributing.md#release-notes))

## Traps when editing modules

- **Mixing inline and child-resource collections causes permanent drift.** Several modules
  deliberately leave the parent's inline attribute unset (`azuread_group.members`, AU `members`)
  because a submodule owns it. Read the banner before "completing" the parent.
  ([why](docs/modules/entra.md#member-submodules))
- **UUID-vs-UPN routing has an unknown-at-plan-time edge.** Keep resource `for_each` keyed on the
  static input map and resolve the routing inside the body. Only the `azuread_user` data source may
  take a value-derived `for_each`. Filtering the map and `for_each`-ing the result is the bug.
  ([why](docs/modules/entra.md#the-unknown-at-plan-time-edge))
- **FortiOS perpetual diffs** are the dominant failure mode in that family — the provider returns
  values you never set. Where a module omits a default, ignores an attribute, or forces sort order,
  that is deliberate. Always explain such a choice in a banner.
  ([why](docs/modules/fortios.md#perpetual-diffs-are-the-dominant-failure-mode))
- **Tautological validation never fires.** `alltrue([for v in values(x) : v.scope != null || true])`
  is always true. Reference the second variable directly — cross-variable validation is legal and
  every module pins `>= 1.15`. ([more](docs/conventions.md#validation))
- **Don't guess enum values you cannot verify.** The fortios provider does not publish accepted values
  for many attributes; a guessed `contains(...)` rejects working configurations.
- **The Aegis tag contract is fixed.** Consumers key off the tag name and value. Read the banner in
  each `main.tf` before touching it. ([why](docs/modules/azure.md#aegis))
- **`prevent_destroy` is hardcoded on three GitHub resources** and is not a bug.
  ([why](docs/modules/github.md#prevent_destroy-is-hardcoded))

## Writing style

Comments explain what the code cannot — why a `lifecycle` block exists, why an attribute is
deliberately unset, a provider bug being worked around. Not prose restating the declaration below it.
Banners are not a mandatory file header; add one when there is something non-obvious to say. Exact
format and the full do/don't list: [conventions.md](docs/conventions.md#comments).

Every variable and output carries a `description` — the tree is at 100% coverage, keep it there.
Validation coverage is uneven (heavy in azure/entra, sparse in fortios); follow the azure/entra
standard in new code. ([more](docs/conventions.md#known-deviations))

## Local noise to ignore

- `.terraform/` provider-cache directories exist on disk and are not source — including their vendored
  READMEs and CHANGELOGs. Don't read them, don't count them, don't edit them.
- `.gitignore` is a ~430-line Visual Studio/.NET template. Everything Terraform-relevant is from
  `# Plugin cache and module cache` onward; the rest is inherited noise.

## Commits

Conventional Commits, scoped to the module or component changed:

```
feat(modules): add FortiGate user setting module
feat(vnet-link): add Azure VNet link module
fix(modules): set default for protected_resources
chore: update provider versions for compatibility
```

Trunk-based: `main` is the only long-lived branch. Work on short-lived branches and open a PR
against `main`. A merge touching `src/` ships a version — `feat:` a minor, anything else a patch. **Mark breaking
changes `<type>!:` or with a `BREAKING CHANGE:` footer** or they release as routine ones — see
[GitVersion.yaml](GitVersion.yaml).

## Keeping docs in sync

- The module inventory lives **only** in `docs/modules/*.md`. Don't reintroduce it elsewhere.
- Adding a module touches five counts, all enforced by `check-docs.py`. All of them, or none — a
  wrong count is worse than no count:
  1. the row itself in the relevant [family guide](docs/modules/), and that file's header count;
  2. the family table in [docs/README.md](docs/README.md#module-reference);
  3. the family table in the root [README.md](README.md);
  4. the `N modules plus N nested submodules` sentence in the root [README.md](README.md) — a
     separate assertion from the table above it, and the one most often missed;
  5. the totals at the top of this file.
- Per-module input/output tables are deliberately not generated — `variables.tf` and `outputs.tf` are
  the reference, and there is no CI to keep generated copies honest.
