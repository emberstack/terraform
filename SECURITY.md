# Security policy

## Reporting a vulnerability

Use GitHub's private vulnerability reporting —
[**Security → Report a vulnerability**](https://github.com/emberstack/terraform/security/advisories/new).
Please do not open a public issue for a security problem.

If that page is unavailable to you, open an issue containing only a request for a private channel —
no details, no reproduction, no affected version. A maintainer will open one and follow up there.

## Scope

This repository is a library of Terraform modules. It runs no service, stores no data, and holds no
credentials. Reports that make sense here are:

- a module that provisions a resource with an insecure default
- a module that places a secret somewhere it should not, or widens access beyond what its inputs imply
- a supply-chain problem in the workflow — a compromised action, an over-scoped token, a mutable ref

## Out of scope

- Vulnerabilities in Terraform itself or in a provider. Report those upstream; if a module needs to
  change in response, open an issue here referencing the upstream advisory.
- Findings that assume an attacker already has write access to the consumer's state backend or cloud
  subscription. At that point the state file is the exposure, not this code.

## Values that reach consumer state by design

Two behaviours look like leaks and are not — they are properties of the upstream provider, documented
at [state considerations](docs/usage.md#state-considerations):

- GitHub Actions secrets are submitted as plaintext and therefore persist in the consumer's state.
- Generated wireless pre-shared keys use `random_password`, whose value lives in state.

Protect the state backend accordingly. If you find a module putting a sensitive value into state
*beyond* these, that is in scope — please report it.
