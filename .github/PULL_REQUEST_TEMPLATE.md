## What changed

<!-- One or two sentences. Which module(s), and why. -->

## Release impact

**Every merge to `main` publishes a version.** There is no staging branch between this pull request
and a consumer's `terraform init`. Pick one:

- [ ] **Additive** — a new module, a new optional input with a default. Title it `feat:`; ships as a
      minor.
- [ ] **Internal or corrective** — a fix, a refactor, docs, CI, a dependency bump. Ships as a patch.
- [ ] **Breaking** — renamed or removed an input or output, changed a default, changed a resource
      address, or tightened validation that previously accepted a working value.

> ⚠️ If this is breaking, put `BREAKING CHANGE:` on its own line in a commit footer — the squashed
> body keeps every commit message, so the footer is matched wherever the subject came from. A `!` is
> only matched in the subject itself: the commit subject when the branch has one commit, the pull
> request title when it has two or more. Otherwise the break ships as an ordinary release.

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
