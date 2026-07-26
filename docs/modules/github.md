# GitHub

3 modules on `integrations/github`, plus seven nested submodules.

## Modules

| Module | What it manages | Submodules |
|---|---|---|
| [`github-res-organization`](../../src/modules/github-res-organization/) | Organization settings, Actions permissions and Actions workflow permissions | `secret`, `variable` |
| [`github-res-repository`](../../src/modules/github-res-repository/) | Repository, its default branch, merge strategy settings and rulesets | `ruleset`, `secret`, `variable` |
| [`github-res-environment`](../../src/modules/github-res-environment/) | Deployment environment | `secret`, `variable` |

Each parent exposes `secrets`, `variables` (and on the repository, `rulesets`) as map inputs and fans
them out to the submodules. Use a submodule directly when the secrets or variables are owned by a
different configuration than the repository itself — otherwise use the parent's map input.

## `prevent_destroy` is hardcoded

Three resources in this family carry `lifecycle { prevent_destroy = true }`, and it is **not**
configurable:

| Resource | Module |
|---|---|
| `github_repository` | `github-res-repository` |
| `github_organization_settings` | `github-res-organization` |
| `github_actions_organization_permissions` | `github-res-organization` |

A repository holds the only copy of its issues, wiki and settings, so accidental replacement is
unrecoverable. The organization resources are worse — one bad plan reverts org-wide security defaults.

**The consequence is that `terraform destroy` fails on any configuration using these modules**, and
removing a repository requires editing the module rather than just the caller. That is intentional
friction. If you hit it, the answer is usually `terraform state rm` and deleting through the GitHub UI,
not a local edit.

`github_repository` additionally ignores `has_downloads` — GitHub still returns a value for that
retired feature, which otherwise produces a permanent diff.

## Secrets end up in your state file

This is the single most important thing to know about this family.

> Actions secrets are submitted to GitHub as plaintext, so they are **persisted in Terraform state**.
> GitHub never returns a secret value, which has two consequences: out-of-band changes are not
> detected, and the module cannot verify what is actually set. Protect the state backend accordingly.

The secret inputs are marked `sensitive`, which keeps values out of plan output and console logs. It
does **not** encrypt state — nothing at the module level can.

Actions **variables** are a separate input and are plaintext by definition: readable by any workflow
in the repository, and returned by the API. Never put a credential in `variables`.

## Rulesets

`github-res-repository` takes rulesets as a map keyed by ruleset name. Each entry sets:

- **`enforcement`** — `active`, `evaluate` (dry-run: reports without blocking) or `disabled`.
  `evaluate` is the safe way to introduce a ruleset to a busy repository.
- **`target`** — `branch`, `tag` or `push`.
- **`conditions`** — `ref_name.include` / `.exclude`, supporting the `~ALL` and `~DEFAULT_BRANCH`
  meta-refs alongside `refs/heads/*` globs.
- **`bypass_actors`** — `actor_type` is `RepositoryRole`, `Team`, `Integration` or
  `OrganizationAdmin`; `bypass_mode` is `always` or `pull_request`.
- **`rules`** — `deletion`, `non_fast_forward`, `required_linear_history` and `creation` are simple
  toggles. Nested objects configure pull request review requirements, required status checks, commit
  message patterns and Copilot code review.

**Omitting a nested rule object leaves that rule unset rather than disabling it.** To turn a rule off,
set its toggle to `false` — don't just delete the block and expect enforcement to stop.

## Actions permissions

`github-res-organization` exposes `allowed_actions_config` for the `selected` case. When
`allowed_actions` is `selected`, the config block is required and controls whether GitHub-owned and
verified actions are permitted alongside your explicit `patterns_allowed` list. Validation on the
module catches the mismatched combinations before the API does.

## New repositories and the default branch

`github-res-repository` sets the default branch with `github_branch_default`, which requires the
branch to exist. The module hardcodes `auto_init` so creation produces an initial commit and that
branch is there to point at.

`auto_init` is create-only at the GitHub API — `PATCH /repos/{owner}/{repo}` discards it — so it is
also in `ignore_changes`. Adopting an existing repository therefore produces no diff at all, and no
full-object PATCH is issued for a field the API ignores.

Two things to know before creating a repository:

- **A new repository is not empty.** `auto_init` produces a `README.md` commit, so a first push from
  a locally initialised repository is a non-fast-forward. Clone rather than push, or reconcile.
- **`default_branch` must match the owner's default branch name.** `auto_init` creates the branch
  named by the organization's *Repository default branch name* setting — usually `main`. Setting
  `default_branch` to anything else on a brand-new repository still fails at `github_branch_default`,
  because `auto_init` did not create that branch. Either align the org setting first, or create with
  the org default and change it afterwards. The setting is not exposed by any resource in
  `integrations/github`, so it cannot be managed here.

`github_branch_default` can also lose a race against GitHub's own eventual consistency on the very
first apply, when the initial commit is not yet queryable. Re-applying clears it.
