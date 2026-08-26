# Kubernetes Namespace

Terraform module for a **single namespace**, owned by Terraform: labels and annotations are managed, drift is detected, and the namespace is removed when the module is.

Reach for it when the namespace carries metadata — Pod Security Admission labels most often — or when it should outlive, and be removed alongside, the workloads installed into it. Where you only need somewhere for a chart to land, [`helm-res-release`](../helm-res-release/) has `create_namespace` and needs no kubernetes provider.

## Usage

### Minimal

```hcl
module "namespace" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/kubernetes-res-namespace?ref=vX.Y.Z"

  name = "kube-cluster-traefik"
}
```

### Pod Security Admission

PSA is configured through ordinary namespace labels, so it goes in `labels` rather than a dedicated input. Ingress controllers and anything wanting host networking or a privileged `securityContext` need this — under the default `restricted` enforcement they fail as pods that never start, not as an apply error.

```hcl
module "namespace" {
  source = "..."

  name = "kube-cluster-traefik"

  labels = {
    "pod-security.kubernetes.io/enforce" = "privileged"
    "pod-security.kubernetes.io/warn"    = "baseline"
  }
}
```

### Ordering a workload behind it

Reference the `name` **output**, not the literal string. That is what creates the dependency edge.

```hcl
module "namespace" {
  source = "..."
  name   = "kube-cluster-traefik"
}

module "release" {
  source    = "git::https://github.com/emberstack/terraform.git//src/modules/helm-res-release?ref=vX.Y.Z"
  namespace = module.namespace.name   # not "kube-cluster-traefik"

  # ...
}
```

### Bounding a stuck deletion

```hcl
timeouts = {
  delete = "10m"
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output carries a description, and CI enforces that.

## Notes

- **⚠️ Destroying this destroys everything inside the namespace.** A namespace delete is recursive and unconditional — workloads, Secrets, ConfigMaps, PVCs, anything reflected in from elsewhere — and Terraform plans it as a single line. There is no per-object confirmation and no partial delete. Point the module only at a namespace whose entire contents you are willing to lose with it.

- **A shared namespace should have no owner among its tenants.** Where several releases install into one namespace, at most one of them can hold delete authority, and usually none of them should. Give the namespace its own module instance and pass the `name` output to each tenant.

- **Deletion blocks on finalizers.** A namespace whose finalizer never clears stays `Terminating` indefinitely and Terraform waits with it. `timeouts.delete` bounds that wait so the apply *fails* rather than hangs. The timeout only changes Terraform's behaviour — the namespace is still stuck afterwards and still needs unwedging by hand; the point is finding out in ten minutes instead of at the CI timeout.

- **Labels and annotations are authoritative.** Both default to `{}` and are managed declaratively, so metadata present on an existing namespace but absent from the call site is removed. When adopting a namespace another controller also writes to, read the live object first and carry its metadata across.

- **`generate_name` is deliberately not exposed.** A namespace whose name is only known after apply cannot be named by whatever installs into it, which is the reason to create one ahead of a workload in the first place.

- **Adopting an existing namespace** works cleanly with `terraform import <address> <name>`. Unlike the sibling Secret module, there is no import artifact here: `wait_for_default_service_account` defaults to `false`, which is also what an import produces, so config and state agree.

- **Full detail:** [Kubernetes family guide](../../../docs/modules/kubernetes.md).
