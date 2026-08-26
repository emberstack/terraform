# Kubernetes Secret

Terraform module for a **single Secret**, including the provider's write-only content variants.

Four inputs carry content and they are not interchangeable — `data` takes plaintext and is base64-encoded for you, `binary_data` takes content that is already base64, and the `_wo` twins of each keep content out of the Terraform state file entirely.

`type` is a **required** input with no default. That is a deliberate break from the usual "omit it and let the provider decide" pattern, and the reason is in [Notes](#notes).

## Usage

### Minimal

```hcl
module "config" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/kubernetes-res-secret?ref=vX.Y.Z"

  name      = "azure-config-file"
  namespace = "kube-cluster-external-dns"
  type      = "Opaque"

  data = {
    "azure.json" = jsonencode({
      subscriptionId               = var.subscription_id
      resourceGroup                = var.dns_resource_group
      tenantId                     = var.tenant_id
      useWorkloadIdentityExtension = true
    })
  }
}
```

### Content that must not reach state

`data_wo` is a write-only attribute: sent to the API server, then discarded. `data_wo_revision` is required alongside it and is what re-sends the value.

```hcl
module "credentials" {
  source = "..."

  name      = "api-credentials"
  namespace = "workloads"
  type      = "Opaque"

  data_wo = {
    "password" = var.api_password
  }
  data_wo_revision = 1   # bump to rotate
}
```

### A TLS Secret

```hcl
type = "kubernetes.io/tls"

data = {
  "tls.crt" = var.certificate_pem
  "tls.key" = var.private_key_pem
}
```

### Ordering it behind a namespace

```hcl
module "secret" {
  source    = "..."
  namespace = module.namespace.name   # not the literal string

  # ...
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output carries a description, and CI enforces that.

## Notes

- **⚠️ `type` is required because it is immutable.** Secret `type` cannot be changed in place, so a wrong value forces a delete-and-recreate. Left optional, an omitted `type` resolves to `Opaque` — and adopting an existing `kubernetes.io/tls` Secret then plans a replace that destroys the certificate. MEASURED against a live cert-manager Secret with the module's defaults: `ACTIONS: ['delete', 'create']`, `replace_paths: [['type']]`, taking `data` and every `cert-manager.io/*` annotation with it. Requiring the input turns a silent destroy into a missing-argument error.

- **⚠️ Labels and annotations are authoritative.** Both default to `{}` and are managed declaratively, so metadata present on an existing Secret but absent from the call site is removed. This is the second half of the trap above: adopting a cert-manager Secret without carrying over its `controller.cert-manager.io/fao` label and its eight `cert-manager.io/*` annotations strips them. Read the live object first when adopting anything a controller also writes to.

- **⚠️ Adopt with `state mv`, not `import`.** `wait_for_service_account_token` is a provider behaviour flag rather than a field on the object, so `import` cannot read it back: it lands null, the configuration resolves it to the provider default of `true`, and the next plan wants an in-place update. Setting the input explicitly does not help — the *before* side is still null. `state mv` carries the stored value across and plans clean.

- **Where content ends up.** `data` and `binary_data` are written to state in cleartext. The provider marks them sensitive, which keeps them out of plan output and CI logs — it does **not** encrypt state, and nothing at the module level can. Protect the state backend accordingly, or use the `_wo` variants.

- **⚠️ `data` is computed, and that cuts two ways.** For a `kubernetes.io/service-account-token` Secret the API server populates it and the provider reads it back, so a Secret of that type has content it was never given. And because a computed attribute reads a null config as *keep what is already there*, **removing `data` from a call site does not empty the Secret** — MEASURED: the plan reports no change to `data` and the content stays in the cluster. Pass `data = {}` to clear it. `binary_data` is not computed and clears on removal.

- **Keys are validated at plan time** against `[-._a-zA-Z0-9]+`, which is the regex the API server itself reports when it rejects one. Without the check the failure arrives at apply.

- **Content is deliberately *not* checked with `base64decode`.** MEASURED: `base64decode("/w==")` returns false — Terraform errors when the decoded bytes are not valid UTF-8, which is precisely what `binary_data` exists to carry. The check would reject working configurations.

- **`data` and `data_wo` are mutually exclusive.** The provider enforces this with a clear message (`"data_wo": conflicts with data`), so the module adds no validation of its own.

- **This module is a poor fit for a Secret a controller owns.** cert-manager rewrites `data` on every renewal, so pointing Terraform at one of its Secrets means the two fight indefinitely. Manage the `Certificate` instead and let cert-manager own the Secret.

- **Full detail:** [Kubernetes family guide](../../../docs/modules/kubernetes.md).
