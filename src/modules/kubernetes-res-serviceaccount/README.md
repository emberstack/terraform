# Kubernetes Service Account

Terraform module for a **single ServiceAccount**, with its associated secrets and image pull secrets.

The module carries no cloud-specific inputs. Azure workload identity, GCP Workload Identity and EKS IRSA are all configured through ordinary metadata, so they go in `labels` and `annotations` — see [Notes](#notes).

## Usage

### Minimal

```hcl
module "service_account" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/kubernetes-res-serviceaccount?ref=vX.Y.Z"

  name      = "service"
  namespace = "latest"
}
```

### Azure workload identity

Both halves are required — the label opts pods into the mutating webhook, the annotation names the identity.

```hcl
module "service_account" {
  source = "..."

  name      = "service"
  namespace = module.namespace.name

  labels = {
    "azure.workload.identity/use" = "true"
  }

  annotations = {
    "azure.workload.identity/client-id" = var.managed_identity_client_id
  }
}
```

### Image pull secrets

```hcl
image_pull_secrets = ["acr-pull"]
```

The Secret must be a `kubernetes.io/dockerconfigjson` in the **same namespace** — an imagePullSecret is never resolved across namespaces.

### Denying API access

```hcl
automount_service_account_token = false
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output carries a description, and CI enforces that.

## Notes

- **Identity federation is metadata, not an input.** For Azure workload identity, set `azure.workload.identity/use = "true"` in `labels` **and** `azure.workload.identity/client-id` in `annotations`. The label alone injects nothing; the annotation alone is never read. A workload that cannot get a token has usually lost one of the pair. Keeping this in metadata is what stops a Kubernetes module from growing an Azure vocabulary.

- **⚠️ Labels and annotations are authoritative.** Both default to `{}` and are managed declaratively, so metadata present on an existing account but absent from the call site is removed — including the workload-identity pair. When adopting an account another controller also writes to, read the live object first and carry its metadata across.

- **`secrets` and `image_pull_secrets` are sets, not lists.** Order carries no meaning to Kubernetes, and a list would invent a diff the first time the API returned them in a different order.

- **`automount_service_account_token` left null means true.** Kubernetes mounts the token by default. Setting it `false` is the blunt way to deny a workload API access — a pod can still opt back in through its own `automountServiceAccountToken`, so it is a default rather than a control.

- **`default_secret_name` is not exposed.** The provider marks it deprecated, so surfacing it would emit a warning on every consumer's `terraform validate`, and it would be blank anyway: Kubernetes 1.24 stopped auto-creating the token Secret it named. Use the TokenRequest API or a hand-made `kubernetes.io/service-account-token` Secret for a token you can read.

- **Adoption imports cleanly.** MEASURED against a live account carrying workload-identity metadata: `terraform import` followed by a plan with `automount_service_account_token` left null gives `ACTIONS: ['no-op']`. There is no equivalent of the Secret module's `wait_for_service_account_token` import artifact, because `automount_service_account_token` is a real field on the object and the provider reads it back.

  ⚠️ Adopting from a `for_each` module means dropping the map key from the address:
  `state mv 'kubernetes_service_account_v1.this["service"]' kubernetes_service_account_v1.this`.

- **`generate_name` is deliberately not exposed.** An account whose name is only known after apply cannot be referenced by the pod spec that has to set `serviceAccountName`.

- **Full detail:** [Kubernetes family guide](../../../docs/modules/kubernetes.md).
