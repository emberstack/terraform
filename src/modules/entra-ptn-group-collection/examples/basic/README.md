# Basic Group Collection Example

Demonstrates the `entra-ptn-group-collection` module creating two security groups (`operators` with 2 members, `readers` with 1 member) in a single deployment.

## What it shows

- Map-keyed `groups` input with two entries
- Required `owners` per group
- Optional `members` per group
- Output structure (`module.ops_groups.groups[<key>]`) — see the parent module's [README](../../README.md) for output access patterns

## How to run

```bash
cd examples/basic
terraform init
terraform plan
```

The example uses placeholder Entra object IDs (`11111111-...`, `22222222-...`, etc.) so `terraform plan` runs without authentication via `-refresh=false`. To actually apply, replace the IDs with real principals from your tenant.
