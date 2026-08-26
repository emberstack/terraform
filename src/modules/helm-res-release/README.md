# Helm Release

Terraform module for a **single Helm release of any chart**. The module is deliberately chart-agnostic: it knows nothing about `traefik` or `cert-manager` values, and passes whatever it is given straight through to `helm_release`.

That is a different bargain from a per-chart module. A `traefik` module can validate that `ingressClass.name` is set; this one cannot. What it buys instead is that adopting a new chart costs a call site rather than a module, and that a chart's own documentation reads as a valid call site.

The module does **not** manage a namespace — see [Namespaces](#namespaces) below.

## Usage

### Minimal

```hcl
module "reloader" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/helm-res-release?ref=vX.Y.Z"

  name          = "reloader"
  namespace     = "kube-cluster-reloader"
  repository    = "https://stakater.github.io/stakater-charts"
  chart         = "reloader"
  chart_version = "2.2.16"
}
```

### Chart values

`values` takes an HCL object and renders it to YAML. `values_yaml` takes raw YAML documents appended after it, which is the equivalent of repeating `helm -f`.

```hcl
module "traefik" {
  source = "..."

  # ...

  values = {
    deployment = { kind = "DaemonSet" }
    service = {
      type        = "LoadBalancer"
      annotations = { "service.beta.kubernetes.io/azure-load-balancer-internal" = "true" }
    }
  }

  values_yaml = [
    <<-YAML
      accessLog:
        enabled: true
        format: json
    YAML
  ]
}
```

### OCI charts

Both forms work and are mutually exclusive — either a repository plus a chart name, or a full reference with no repository.

```hcl
# repository + chart name
repository = "oci://ghcr.io/emberstack/helm-charts"
chart      = "generic"

# full reference, no repository
chart = "oci://ghcr.io/emberstack/helm-charts/generic"
```

### A secret that must not reach state

`set_wo` is a write-only attribute: sent to Helm, then discarded. `set_wo_revision` is required alongside it and is what re-sends the value.

```hcl
module "app" {
  source = "..."

  # ...

  set_wo = [{
    name  = "auth.adminPassword"
    value = var.admin_password
  }]
  set_wo_revision = 1   # bump to rotate
}
```

### Letting the release create its namespace

```hcl
namespace        = "kube-cluster-reloader"
create_namespace = true
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output carries a description, and CI enforces that.

## Notes

- **No default is invented here.** Every optional input defaults to `null`, so Helm's own default applies and the module contributes none of its own. The tempting alternative — defaulting `upgrade_install` to `true` because it is usually wanted — makes the module lie: someone comparing a call site against Helm's documentation would find behaviour that appears in neither, and there is no way to opt back out of a default that lives inside a module. The consequence for callers is that `atomic`, `upgrade_install` and `max_history` have to be asked for explicitly — but not `wait`, which the provider already defaults to `true` alongside `timeout = 300` (MEASURED against v3.2), so an apply blocks on readiness for five minutes unless you switch it off. `create_namespace` is the single exception, and it states Helm's own default rather than a new one.

- **`values` is typed `any`, not `map(any)`.** Terraform unifies map element types, and two chart values of different shapes have no common base type — `map(any)` fails with *"all map elements must have the same type"*. Wrapping does not rescue it either: a `map(object({ values = any }))` fails with *"cannot find a common base type for all elements"*. `any` passes the object through untouched.

- **Where a secret ends up.** `values`, `values_yaml` and `set` are cleartext in state and in plan output. `set_sensitive` is redacted from plan output but **still written to state**. Only `set_wo` keeps a value out of the state file. None of that reaches Helm's own copy: every revision — rendered manifests and merged values alike — is stored in a Secret named `sh.helm.release.v1.<name>.v<revision>` in the release namespace, readable by anyone who can read Secrets there.

- **`set_wo` costs drift detection.** Terraform cannot read a write-only value back, so it cannot notice one changed. The module requires `set_wo_revision` for exactly that reason — without it, rotating a secret plans clean and does nothing.

- **`version` is spelled `chart_version`.** Terraform reserves `version` as a variable name for module block meta-arguments. Leaving it null resolves the latest chart at apply time, which makes the release irreproducible — pin it.

- <a id="namespaces"></a>**Namespaces.** `create_namespace` asks Helm for a bare namespace: no labels, no annotations, and it is left behind on uninstall. A namespace that carries metadata, or that should be removed along with what it holds, belongs to [`kubernetes-res-namespace`](../kubernetes-res-namespace/) — pass its `name` output rather than repeating the string, so the reference orders the two. Keeping the namespace out of this module is also what keeps it on a single provider.

- **Adopting a release from another module.** The resource is `helm_release.this`. Where a release is already managed elsewhere under a different resource name, `terraform state mv` is enough — no cluster-side change is involved.

- **Full detail** on secret handling and namespace trade-offs: [Helm family guide](../../../docs/modules/helm.md).
