## What changed

<!-- One or two sentences. Which module(s), and why. -->

## Release impact

**Every merge to `main` publishes a version.** There is no staging branch between this pull request
and a consumer's `terraform init`. Pick one:

- [ ] **Additive** — a new module, a new optional input with a default. Title it `feat:`; ships as a
      minor.
- [ ] **Internal or corrective** — a fix, a refactor, docs, CI, a dependency bump. Ships as a patch.
- [ ] **Breaking** — renamed or removed an input or output, changed a default, changed a resource
      address, or tightened validation that previously accepted a working value. Still ships as a
      minor or a patch; majors are cut deliberately, not inferred.

> ⚠️ A breaking change does **not** bump the major here, so the release notes are the only place a
> consumer will see it. Put `BREAKING CHANGE:` on its own line in a commit footer — the squashed body
> keeps every commit message, so the footer survives wherever the subject came from. A `!` is only
> matched in the subject itself: the commit subject on a single-commit branch, the pull request title
> when there are two or more. Unmarked, the break is invisible.

## Checks run locally

- [ ] `terraform fmt -recursive`
- [ ] `python .github/scripts/check-docs.py`
- [ ] `terraform init -backend=false && terraform validate` in each module touched
- [ ] New module: added to the family guide in
      [`docs/modules/`](https://github.com/emberstack/terraform/tree/main/docs/modules) and all five
      counts updated — see
      [adding a module](https://github.com/emberstack/terraform/blob/main/docs/contributing.md#adding-a-module)

## Anything reviewers should look at twice

<!-- Perpetual-diff workarounds, lifecycle blocks, deliberately unset attributes. Delete if none. -->
