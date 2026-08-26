# Kubernetes Manifest

Terraform module for **one Kubernetes object of any kind**, given as a manifest. For custom resources, and for anything the provider has no first-class resource for.

Where a first-class resource exists — a Namespace, a Secret, a ServiceAccount — prefer it. Those have real schemas, plan without cluster access, and do not carry the constraints below.

## Usage

### A custom resource

```hcl
module "cluster_issuer" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/kubernetes-res-manifest?ref=vX.Y.Z"

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = "platform@example.com"
        privateKeySecretRef = {
          name = "letsencrypt-account-key"
        }
        solvers = [{
          dns01 = {
            azureDNS = {
              subscriptionID    = var.subscription_id
              resourceGroupName = var.dns_resource_group
              hostedZoneName    = var.zone_name
              environment       = "AzurePublicCloud"
            }
          }
        }]
      }
    }
  }
}
```

### Waiting for the object to become ready

Always bound a wait with a timeout — a resource that never reconciles otherwise blocks until the pipeline gives up.

```hcl
wait = {
  condition = [{
    type   = "Ready"
    status = "True"
  }]
}

timeouts = {
  create = "5m"
}
```

### Letting a controller own part of the object

```hcl
computed_fields = [
  "metadata.annotations",
  "metadata.labels",
  "spec.replicas",     # owned by an autoscaler
]
```

### Adopting an object another manager created

```hcl
field_manager = {
  name            = "terraform"
  force_conflicts = true
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output carries a description, and CI enforces that.

## Notes

- **⚠️ The cluster must be reachable at plan time.** The provider fetches the OpenAPI schema for the manifest's `kind` to build its type, so this resource cannot be created in the same apply as the cluster, and a `run --all plan` against a tier whose cluster does not exist yet fails on these units.

- **⚠️ A CRD must exist before a CR of that kind can be PLANNED.** Terraform cannot apply a CRD and a custom resource of it in one run — at plan time the kind is absent from the OpenAPI document and the plan fails outright. Order the CRD into an earlier unit; where a Helm chart installs its own CRDs, depend on that release rather than sitting beside it.

- **⚠️ Adopt with `state mv`, not `import`.** `import` populates `object` but leaves `manifest` **null**, because the provider cannot know which subset of the object you mean to manage. MEASURED against a live ClusterIssuer, the next plan reads `ACTIONS: ['update']` with `manifest: null -> {...}`. `state mv` from another configuration carries `manifest` across and plans clean.

- **`namespace` is null for a cluster-scoped kind.** The output reads `metadata.namespace` off the applied object through a `try`, so a ClusterIssuer, ClusterRole or CRD returns null rather than failing. MEASURED: `name -> "letsencrypt"`, `namespace -> None`.

- **`manifest` is typed `any`.** Terraform unifies map element types, and two manifests of different kinds have no common base type, so any narrower constraint would reject valid input. The cost is that a malformed manifest is caught by the API server rather than a type check — the module validates only `apiVersion`, `kind` and `metadata.name`.

- **`computed_fields` is how you stop fighting a controller.** The provider defaults to `["metadata.annotations", "metadata.labels"]`, which covers what `kubectl` adds and nothing more. Widen it when something else owns part of the object, or every reconcile shows up as drift.

- **`generate_name` is not supported.** A name known only after apply cannot be referenced by whatever depends on it, so `metadata.name` is validated as required.

- **`wait_for` is not exposed** — the provider marks it deprecated in favour of the `wait` block.

- **Full detail:** [Kubernetes family guide](../../../docs/modules/kubernetes.md).
