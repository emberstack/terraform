# Contributing

## Before you change anything

**Every merge that touches `src/` is a release.** This repository is trunk-based: `main` is the only
long-lived branch, and merging a module change to it tags a version and publishes it automatically.
There is no staging branch between your PR and a consumer's `terraform init`.

Docs, CI and repository config do not publish. A consumer resolves `//src/modules/<name>` at a ref,
so nothing outside `src/` reaches them — numbering it would ship a release identical to the one
before it. Those commits are not stranded: they stay unreleased until the next module change carries
them out, and the notes cover the whole range since the last tag, so they still appear.

That makes interface stability the default posture:

- Prefer **additive** changes with defaults over anything that alters an existing contract.
- Renaming or removing a variable or output is a breaking change. So is changing a default, changing
  a resource address, or tightening a validation rule that previously accepted a working value.
- If a change *must* break, say so explicitly in the commit body.

**Keep consumer identifiers out of this repository.** It is a public module library. No customer
names, real hostnames, switch or SSID names, domains, serial numbers, directory object IDs, or
filesystem paths from downstream repositories. Use neutral placeholders: `example.com`, `core-sw-01`,
`corp-nac`, `rg-example`.

## What CI runs

[`.github/workflows/pipeline.yaml`](../.github/workflows/pipeline.yaml) runs on every push and pull
request against `main`:

| Job | What it does |
|---|---|
| `discovery` | Resolves the version from GitVersion and decides whether this run releases |
| `build` | `terraform fmt`, the consistency checks, then `init -backend=false` + `validate` over [what actually changed](#what-triggers-what) |
| `gate` | Aggregates the results into one always-reporting status — **this is the required check** |
| `release` | Tags and publishes — runs behind `gate`, on `main` only (push, or break-glass dispatch), when something under `src/` changed and `discovery` resolved an unreleased version |

`build` does not recompute the version; it is resolved once in `discovery` and read from its outputs.

### The required check is `gate`, not `build`

`build` is skipped when a change touches neither modules nor docs, and a required check that never
reports leaves the pull request permanently unmergeable. `gate` runs with `if: always()`, so it
reports on every run, and fails if any job it depends on failed or was cancelled. Point branch
protection at it and nothing else.

The required context string is **`gate`**.

### Branch protection

Not yet applied. **Merge the pipeline and let it run once first**, or `gate` will not exist as a
selectable context.

```bash
gh api repos/emberstack/terraform/rulesets -X POST --input - <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request",
      "parameters": { "required_approving_review_count": 0,
                      "dismiss_stale_reviews_on_push": false,
                      "require_code_owner_review": false,
                      "require_last_push_approval": false,
                      "required_review_thread_resolution": false } },
    { "type": "required_status_checks",
      "parameters": { "strict_required_status_checks_policy": false,
                      "required_status_checks": [ { "context": "gate" } ] } }
  ]
}
JSON
```

Release tags, so a published version can never be moved or deleted. `creation` is deliberately absent
— the pipeline has to be able to tag:

```bash
gh api repos/emberstack/terraform/rulesets -X POST --input - <<'JSON'
{
  "name": "release-tags",
  "target": "tag",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "rules": [ { "type": "deletion" }, { "type": "non_fast_forward" } ]
}
JSON
```

Notes:

- **0 required approvals** is deliberate. With a single collaborator, requiring one locks you out of
  your own repository; the CI check does the gating.
- No bypass actors. Admins are bound too — that is the point. To force a fix through, set the
  ruleset's `enforcement` to `disabled`, do the work, set it back.
- `gh api repos/emberstack/terraform/rulesets` lists them; `... /rulesets/<id> -X DELETE` removes one.

### Three repository settings worth reviewing at the same time

Two want changing and one wants deliberately leaving alone. All three matter more on a public
repository than a private one:

```bash
# The default GITHUB_TOKEN is currently `write`. This workflow overrides it to
# `read`, but any future workflow added without an explicit `permissions:` block
# would inherit a write token.
gh api repos/emberstack/terraform/actions/permissions/workflow -X PUT \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
```

```bash
# Enable private vulnerability reporting. SECURITY.md names it as the only way
# to report a vulnerability, and it is OFF by default — until this runs, that
# link is a dead end for anyone trying to disclose responsibly.
gh api repos/emberstack/terraform/private-vulnerability-reporting -X PUT
```

```bash
# LEAVE THIS ONE OFF. Requiring actions to be pinned to a commit SHA would fail
# every workflow run, because every action here is pinned to a version tag by
# choice — see "How actions are pinned". Listed so the reasoning is on record
# when someone finds the setting and wonders why it is not enabled.
gh api repos/emberstack/terraform/actions/permissions -X PUT \
  -F enabled=true -f allowed_actions=all -F sha_pinning_required=true
```

⚠️ **Squash-merge drops the `!` marker.** The repository's squash title is `COMMIT_OR_PR_TITLE`, so on
a multi-commit pull request the squashed subject becomes the *PR title*, and a `feat!:` written only
in a commit subject is lost. That no longer changes the version — `feat!:` and `feat:` are both a
minor — but it silently drops the change out of the **Breaking Changes** section of the release
notes, which is now the only place a consumer learns of it. The squash body is `COMMIT_MESSAGES`, so
a `BREAKING CHANGE:` footer does survive. **Under squash-merge, use the footer** — the one marker
that survives whatever the title resolves to. A `!` only lands where that setting reads from: the
*commit subject* on a single-commit branch, the *pull request title* on a multi-commit one.

All three checks live in one job on purpose: split across separate jobs, per-job VM and checkout
overhead costs more runner time than the parallelism saves. The steps use `!cancelled()`, so a
formatting failure still reports the docs and validate results: **one push surfaces every problem**,
not just the first.

No cloud credentials are involved — validation resolves providers from the registry and checks
configuration statically.

### What triggers what

`discovery` classifies the change with `dorny/paths-filter` and `build` skips the steps that cannot
be affected:

| Changed | `fmt` + `validate` | consistency checks | releases |
|---|---|---|---|
| `src/**` | yes | yes | **yes** |
| `docs/**`, `*.md` | no | yes | no |
| `.github/workflows/pipeline.yaml` | yes | yes | no |
| `.github/**`, `LICENSE`, `GitVersion.yaml`, `renovate.json`, `cliff.toml` | no | yes | no |
| anything else | no | no — `build` is skipped entirely | no |

Three filters, not two. `src` exists only to gate the release and is deliberately narrower than
`modules`: a change to `pipeline.yaml` has to re-validate the whole tree, but re-validating is not a
reason to publish — no module moved. `LICENSE` is in `docs` for the same reason; it is worth a
consistency check, and a licence change can ride out with the next module release.

The `docs` filter is wider than the set of files the consistency check *reads*, because it must also
cover every path the documentation *links to*. `LICENSE`, `GitVersion.yaml`, `renovate.json`,
`cliff.toml` and the chore workflows are all link targets: move one without touching a `.md` file
and `build` would skip, the merge would go green, and the broken link would fail the next
contributor's unrelated pull request instead.

The consistency checks run whenever `build` runs, because they validate module structure — the four
required files, and a `description` on every variable and output — as well as documentation. A new
module with a missing `outputs.tf` has to fail CI, not review.

**Anything under `src/` rebuilds all of `src`.** Selecting individual modules would be wrong here:
they source each other by relative path, so editing `entra-res-group/modules/member` can break
`entra-res-group`, `entra-ptn-group-collection` and its example — three directories nobody touched.
Validating the whole tree removes that question rather than trying to answer it with a dependency
graph.

A merge that touches neither modules nor docs skips `build` entirely — and no longer releases
either, because the release gate asks for a change under `src/`. That closes a hole worth knowing
about: `release` used to sit beside `gate` with its own copy of the pass check, and a *skipped*
build is neither failed nor cancelled — so before the `src` gate a `.gitignore` edit published a
version having run no checks at all. `release` now depends on `gate` instead, which is the only
place that decides whether everything passed.

If the sweep ever resolves zero directories it fails rather than reporting a green tick.

### Why there is no `actions/cache`

`build` sets `TF_PLUGIN_CACHE_DIR` so every `init` shares one provider directory. That part is not
optional — without it Terraform downloads a private copy of every provider per module, which runs to
gigabytes and a dozen copies of azurerm.

Persisting that directory between runs with `actions/cache` is a different question, and the answer
is no. `TF_PLUGIN_CACHE_DIR` never evicts: on each provider bump the restore-key pulls the previous
cache, Terraform adds the new version alongside the old, and the whole directory is saved again. The
cache grows by another provider-sized chunk every bump, forever, and never shrinks.

If builds ever get slow enough to revisit this, cache a **pinned** set of provider versions rather
than the whole plugin directory.

The commands below are the same checks, run locally. Run them before pushing — CI is a backstop, not
a substitute.

## Local checks

### Format

```bash
terraform fmt -recursive
```

Run from the repository root before committing. `terraform fmt -recursive -check` exits non-zero if
anything is unformatted.

### Consistency checks

```bash
python .github/scripts/check-docs.py
```

The one check that runs on **every** build, including changes that touch no Terraform at all. It
verifies three things and exits non-zero on any of them:

| | |
|---|---|
| Links and anchors | every relative link and `#anchor` in the documentation resolves |
| Inventory | every module directory on disk appears in a family guide, and vice versa |
| Structure | the four required files per module, and a `description` on every variable and output |

Run it from the repository root. It needs no providers, no network and no credentials, so it is the
cheapest of the three to run and the one most likely to catch you out — a renamed heading or a new
module both fail it.

It deliberately does **not** check module counts, because the docs deliberately don't state any —
see [Keeping docs in sync](../CLAUDE.md#keeping-docs-in-sync).

### Validate a single module

```bash
cd src/modules/entra-res-group
terraform init -backend=false
terraform validate
```

`terraform validate` needs `init` first to resolve providers and relative submodule sources.
`-backend=false` is sufficient — no module here has a backend.

Where a module has an `examples/basic/`, validate through it instead. The example supplies the
provider configuration a bare module lacks:

```bash
cd src/modules/entra-ptn-group-collection/examples/basic
terraform init
terraform validate
```

### Sweep the whole tree

The same directories CI covers — every module directory plus `examples/basic`.
**Set a plugin cache first** or you will download the same providers once per directory:

```bash
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
mkdir -p "$TF_PLUGIN_CACHE_DIR"

find src/modules -name '*.tf' -not -path '*/.terraform/*' -printf '%h\n' | sort -u | while read -r d; do
  (cd "$d" && terraform init -backend=false -upgrade >/dev/null && terraform validate) \
    || echo "FAILED: $d"
done
```

### The stale lock trap

`.terraform.lock.hcl` is gitignored but still written locally. After a version floor bump in
`versions.tf`, an old local lock fails `init` with:

```
locked provider ... does not match configured version constraint
```

Re-run with `terraform init -upgrade`. This is a local artefact, never a repository defect — don't
"fix" `versions.tf` to satisfy a stale lock.

## Adding a module

1. **Name it** to match the [naming convention](conventions.md#naming) exactly, and place it as a
   sibling in `src/modules/`. FortiGate modules need the `fortigate` platform segment.
2. **Create all four files** — `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` — even if one is
   short. Never fold them together.
3. **Pin versions** in `versions.tf`: `required_version` matching the rest of the tree, and a provider constraint with
   both a floor and an upper bound below the next major.
4. **Describe every variable and output.** The tree is at 100% description coverage; keep it there.
5. **Validate inputs** — length bounds, enums, regex — to the azure/entra standard, except where the
   provider schema does not let you prove the accepted values.
6. **Add a banner** to `main.tf` only if there is non-obvious behaviour to explain.
7. **Add the module** to the relevant family guide in [`docs/modules/`](modules/) — one row, and
   that is the whole documentation obligation. No counts to update anywhere; don't add any.
8. `terraform fmt`, `init -backend=false`, `validate`, and
   [`check-docs.py`](#consistency-checks) — the last one is what verifies steps 2, 4 and 7.

A `README.md` and an `examples/basic/` are welcome but not required — most modules have neither,
so a new module without them is not an outlier.

Where a parent gains a submodule, add a **Submodules** section to the parent's README if it has one.

## Commits

Conventional Commits, scoped to the module or component changed:

```
feat(modules): add FortiGate user setting module
feat(vnet-link): add Azure VNet link module
fix(modules): set default for protected_resources
chore: update provider versions for compatibility
```

## Branches

Trunk-based. `main` is the only long-lived branch and always reflects the released library. Work on
short-lived branches — `feat/…`, `fix/…` — and open a pull request against `main`. Both pipeline
triggers are scoped to `main`, so a branch builds once a pull request is open against it and never
before. Nothing but `main` publishes, and the version `discovery` reports on a pull request is the
plain `X.Y.Z` that merging would release — there are no prerelease versions in this repository.

## Releases

The pipeline tags and publishes a GitHub Release on every push to `main` **that changes something
under `src/`**. The version comes from [GitVersion.yaml](../GitVersion.yaml):

| Merge to `main` | Bump |
|---|---|
| `feat:` in the subject — with or without a `!` — or `+semver: minor` | **minor** |
| anything else — `fix:`, `fix!:`, `refactor:`, `docs:`, `chore:`, an unconventional subject | **patch** |
| `+semver: major` on a line of its own, or a bumped `next-version` | **major** |

Only `feat:` earns a minor because a new module is additive surface that breaks no existing caller —
the definition of a minor. A fix or a dependency bump is not, and numbering one as a minor tells a
consumer pinned to a tag that there is something new to adopt when there is not. A subject matching
neither pattern falls through to patch, so a sloppy message under-reports rather than inflates.

A `docs:` or `chore:` merge that leaves `src/` alone gets no version of its own. It is not lost —
the next module change releases the whole range since the last tag, and its notes list every commit
in it. Only a change a consumer can actually resolve earns a number.

```
v0.1.0 --feat--> v0.2.0 --fix--> v0.2.1 --feat!--> v0.3.0 --+semver: major--> v1.0.0
```

### A major is asked for, never inferred

**`<type>!:` and a `BREAKING CHANGE:` footer do not bump the major.** They mark the change as
breaking in the [release notes](#release-notes) and nothing more. On a `0.x` library that is the
useful behaviour: breaks accumulate and get released together as a considered major, rather than
each one graduating the library the moment somebody types a `!`.

Two ways to cut one, both deliberate:

```yaml
# GitVersion.yaml — set it in the same pull request as the change.
next-version: 1.0.0
```

```
# ...or a commit footer, on a line of its own.
+semver: major
```

`next-version` is a floor, so it wins over whatever the subject says and the next release takes it
exactly. It then goes inert by itself: once the tag exists it sits below it and stops mattering, so
`v1.0.0` is followed by `v1.0.1` and `v1.1.0` normally, whether or not you tidy the line away.

> ⚠️ **`next-version` is a switch, not a plan.** While it is set and not yet reached, *every* merge
> releases it — a `docs:` typo fix included. Set it in the pull request that carries the change, not
> ahead of time.

**Still mark breaking changes.** The version no longer carries the signal, so the notes are the only
place a consumer pinned to a tag can read it. Use `feat(modules)!: rename input` or a
`BREAKING CHANGE:` footer — under squash-merge only the latter always survives.

One nuance worth knowing: GitVersion computes a single version for the whole range since the last
tag, not one per commit. Because the pipeline tags every push, that range is normally one merge. If a
release is ever skipped — CI red, a cancelled run — the next successful release covers both merges
under one version, and the strongest bump in the range wins: three `fix:` commits and one `feat:`
release together as a minor. That is correct; a version numbers a release, not a commit. It also means
**a patch release never contains a `feat:`**, which is the guarantee a consumer pinned to a tag reads
off the version number.

**Previewing a version** needs nothing special: `discovery` runs on every pull request and writes the
version it would release into the run summary.

**There is no version override.** The workflow takes no inputs. Versions are derived from tags and
commit messages, and a hand-picked version desynchronises the two permanently — the manual tag becomes
the base GitVersion derives the *next* version from, so a typo shifts the whole line and cannot be
walked back without deleting a published tag.

### Release notes

Notes are generated by [git-cliff](https://git-cliff.org) from the commits in the release,
configured by [cliff.toml](../cliff.toml). There is no committed `CHANGELOG.md` — on a repo that
publishes every merge the releases page already is one, and a file would be a second copy to keep
honest.

Commits are grouped by type: breaking changes first, then features, fixes, performance,
refactoring, CI, docs, tests and reverts. Maintenance and dependency bumps collapse behind a
`<details>` toggle, so a release dominated by Renovate still shows the one `fix:` that matters. A
subject matching no convention lands under **Other Changes** rather than disappearing — it
released, so it gets listed. Every set of notes ends with the `?ref=` pin for that exact version,
because a module library is only useful if you can copy the thing you just published.

> ⚠️ **`cliff.toml` and `GitVersion.yaml` diverge on purpose — keep the anchoring identical.**
> git-cliff flags all three markers (`<type>!:`, a `BREAKING CHANGE:` footer, `+semver: major`) as
> breaking; GitVersion bumps the major for the last one only. That gap is the design — it is what
> lets a break be announced without forcing a major. What must not drift is the `(?m)` anchoring:
> a marker on a body line has to mean the same thing in both, or the notes and the number describe
> different commits.

### When a release does not happen

| What happened | Recovery |
|---|---|
| A job failed, or the runner died mid-run | Re-run from the Actions UI, or `gh run rerun <run-id> --failed`. Replays the same commit and event payload. |
| The run never started — the workflow file itself was broken | Push the fix. That merge triggers the pipeline and releases normally. |
| Re-run is no longer offered, because the run aged out | Run the workflow manually from the Actions tab against `main`. |
| A merge landed while CI was red | Nothing to do. The next successful release covers both merges under one version. |
| A tag exists with no release behind it | Generate the notes and attach them by hand — `GITHUB_TOKEN=$(gh auth token) git cliff --tag v<x.y.z> v<prev>..v<x.y.z> --strip header -o notes.md` then `gh release create v<x.y.z> --notes-file notes.md`. The pipeline will **not** backfill it — `discovery` skips any version whose tag already exists. |

The manual trigger takes no inputs on purpose. It re-runs the pipeline against the current head of the
selected branch, derives the version the same way a push would, and the existing-tag check makes a
dispatch against an already-released commit a no-op rather than a duplicate.

## Dependency updates

Renovate runs from this repository —
[`.github/workflows/chore-renovate.yaml`](../.github/workflows/chore-renovate.yaml), configured by
[`renovate.json`](../renovate.json). The Mend GitHub App is deliberately not installed, so no third
party holds a standing grant here. The job runs on a GitHub-hosted runner, and the org PAT is handed
to the pinned action for the length of one step rather than left sitting on the repository.

| | |
|---|---|
| Schedule | 02:00 on weekdays, every push to `main`, plus manual dispatch with a log-level choice |
| Actions | one weekly batch, reviewed by hand. Renovate's own action updates in a separate group |
| Providers | **not automated** — the declared range is never rewritten |
| Terraform (CI) | patch opens a pull request; minor and major wait on the dashboard |
| Branches | `chore/renovate/…`, commits prefixed `chore(deps):` |

**Provider constraint bumps are not automated.** A floor in `versions.tf` is a compatibility promise
to consumers, not a number to keep current — raising a floor forces every consumer to upgrade.
With `rangeStrategy: in-range-only` Renovate never rewrites a declared range, so no provider pull
request opens and nothing waits on the dashboard either.

That covers `hashicorp/azurerm` majors too. The azurerm major cap in `versions.tf` is unchanged, and moving
to v5 stays a deliberate manual edit — the `management_group_id` migration that used to block it is
done, but the remaining azurerm modules have not been checked against v5.

**Terraform itself is tracked in two places, differently.** The `required_version` in every
`versions.tf` is picked up by the built-in `terraform` manager, so the same rule leaves it alone.
`TERRAFORM_VERSION` in `pipeline.yaml` is a plain YAML value that no built-in manager can see, so a
`customManagers` regex matches it and resolves it against `hashicorp/terraform` releases.

That pin is deliberately the newest patch of the `required_version` floor, so the pipeline proves the
floor is honest rather than testing something newer than the modules declare. A patch keeps that true
and opens on its own. A minor or major would quietly break it — CI would start validating against a
Terraform the modules never promised — so it waits for a tick on the dashboard, and taking it means
raising the floor in every `versions.tf` with it as a marked breaking change.

A pull request that edits `renovate.json` is schema-checked by a separate `validate-config` job that
holds **no credentials at all**, so the one file a pull request fully controls never reaches the step
carrying the PAT. A malformed file or an invalid option fails on the pull request that introduced it
rather than at 02:00 the next morning. Know its limit: the validator reads the schema and resolves no
dependencies, so a config that parses and is still wrong gets through. Fork pull requests run it like
anyone else's — there is no secret in that job to withhold.

The `renovate` job itself does not run on `pull_request` at all, and that is what keeps the PAT away
from unreviewed code — including Renovate's own self-update pull request, whose only change is the
version of `renovatebot/github-action` in the workflow file. The `paths` filter on the trigger is a
convenience, not a security boundary: a `pull_request` run evaluates the workflow as the pull request
has it, so the pull request controls that filter too.

Renovate authenticates with the org-level `ES_GITHUB_PAT`. That matters beyond access: pull requests
opened with the default `GITHUB_TOKEN` do not trigger other workflows, so Renovate's own pull requests
would never run `pipeline`. With the PAT they are validated like anyone else's. Moving to a GitHub App
token would be the stronger option if one is ever registered for the organisation.

## Stale issues and pull requests

[`.github/workflows/chore-cleanup-stale.yaml`](../.github/workflows/chore-cleanup-stale.yaml)
sweeps daily at 02:00 UTC:

| | Stale after | Closed after |
|---|---|---|
| Issues | 60 days | 14 further days |
| Pull requests | 30 days | 14 further days |

Issues get the longer fuse deliberately. An unanswered bug report is usually waiting on a maintainer,
and closing it charges the reporter for that; an abandoned pull request rots against `main`, and
reopening costs its author nothing. Closed issues use `not_planned`, so being aged out is visibly
distinct from being fixed.

Never marked:

- anything labelled `pinned` or `security`
- issues labelled `good first issue` or `help wanted` — those are advertisements, meant to sit open
  until a stranger picks them up
- anything in a milestone, which is planned work rather than drift
- draft pull requests

A comment from anyone resets the clock, and the sweep processes oldest first so a backlog drains
predictably under the 100-operation cap.

**A closed item is not a rejected one.** Comment on a closed issue and a maintainer will reopen it —
reopening an issue the bot closed needs the Triage role, so it is not something a reporter can do
themselves. A pull request is different: its author can reopen it directly, and the branch is
untouched either way.

## Workflow run retention

[`.github/workflows/chore-cleanup-workflow-runs.yaml`](../.github/workflows/chore-cleanup-workflow-runs.yaml)
deletes workflow runs older than **30 days** at 04:00 UTC, keeping a minimum of **5** runs per
workflow so a rarely-triggered one never disappears entirely.

This removes the run records themselves, which is a different thing from GitHub's built-in *log and
artifact* retention — that is a repository setting, defaults to 90 days, and is untouched here.

⚠️ Deleting a run destroys the evidence of what CI did for a given tag. The run that validated and
published `v0.3.0` is the only record of which Terraform version and which providers it was checked
against. The release, the tag and the
commit all survive; the proof does not.

### How actions are pinned

Every action is pinned to a **version tag, never a commit SHA**. Most sit on a major tag and pick up
patches silently; the rest pin an exact version and get a Renovate pull request for each release
instead. The workflows themselves are the list.

Tags are mutable, so this is a deliberate trade: readable diffs and a legible upgrade history, against
trusting each action's owner not to move a tag underneath us. It also means the `sha_pinning_required`
repository setting must stay **off** — switching it on fails every workflow run until the convention
changes.
