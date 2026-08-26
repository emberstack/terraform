# Kubernetes

Modules on the `hashicorp/kubernetes` provider.

## Modules

| Module | What it manages | Submodules |
|---|---|---|
| [`kubernetes-res-namespace`](../../src/modules/kubernetes-res-namespace/) | A single namespace, with its labels and annotations | — |
| [`kubernetes-res-secret`](../../src/modules/kubernetes-res-secret/) | A single Secret, including its write-only content variants | — |
| [`kubernetes-res-serviceaccount`](../../src/modules/kubernetes-res-serviceaccount/) | A single ServiceAccount, with its secrets and image pull secrets | — |

## ⚠️ Destroying a namespace destroys everything in it

A namespace delete is recursive and unconditional. Workloads, Secrets, ConfigMaps, PVCs, anything
reflected in from another namespace — all of it goes, and Terraform plans it as a single line:

```
# module.namespace.kubernetes_namespace_v1.this will be destroyed
```

There is no per-object confirmation and no partial delete. Point the module only at a namespace whose
entire contents you are willing to lose with it, and think twice where several releases share one —
at most one of them can be the owner, and often none of them should be.

Where a namespace should outlive everything installed into it, do not manage it here at all. Either
let the workload create a bare one (`helm-res-release` has `create_namespace` for that) or leave it
outside Terraform.

## Deletion blocks on finalizers

A namespace stuck on a finalizer stays `Terminating` indefinitely, and Terraform waits with it.
`timeouts.delete` bounds that wait so a wedged namespace fails the apply instead of hanging it:

```hcl
timeouts = {
  delete = "10m"
}
```

The timeout only changes how Terraform behaves. The namespace is still stuck afterwards and still
needs its finalizer cleared by hand — the point is that you find out in ten minutes rather than
discovering it when the pipeline times out.

## Pod Security Admission is a label

PSA is configured through ordinary namespace labels, so it belongs in `labels` rather than in a
separate input:

```hcl
labels = {
  "pod-security.kubernetes.io/enforce" = "privileged"
  "pod-security.kubernetes.io/warn"    = "baseline"
}
```

Charts that need host networking or a privileged securityContext — ingress controllers most often —
fail to schedule under the default `restricted` enforcement, and the failure surfaces as pods that
never start rather than as an apply error.

## Ordering a workload behind the namespace

Reference the `name` **output** rather than repeating the string. That is what creates the dependency
edge, so nothing installs into a namespace Terraform has not finished creating:

```hcl
module "namespace" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/kubernetes-res-namespace?ref=vX.Y.Z"
  name   = "kube-cluster-traefik"
}

module "release" {
  source    = "git::https://github.com/emberstack/terraform.git//src/modules/helm-res-release?ref=vX.Y.Z"
  namespace = module.namespace.name   # not "kube-cluster-traefik"
  # ...
}
```

Passing the literal string to both leaves the two unordered, and the release then races the namespace
on a first apply.

## Four ways to put content in a Secret

`kubernetes-res-secret` takes content through four inputs, and they are not interchangeable:

| Input | Encoding | In state |
|---|---|---|
| `data` | **plaintext** — the provider base64-encodes it | yes, marked sensitive |
| `binary_data` | **already base64** | yes, marked sensitive |
| `data_wo` | plaintext, write-only | **no** |
| `binary_data_wo` | base64, write-only | **no** |

⚠️ **Passing base64 to `data` double-encodes it.** The Secret applies cleanly and the consuming pod
reads gibberish, so the failure shows up in the workload rather than in the plan.

`data` and `binary_data` are written to state in cleartext. The provider marks them sensitive, which
keeps them out of plan output and CI logs — it does **not** encrypt state, and nothing at the module
level can. Protect the state backend accordingly.

The `_wo` variants keep content out of the state file entirely, at the cost of drift detection:
Terraform cannot read a write-only value back, so it cannot notice one changed. The matching
`_wo_revision` is what re-sends it, and the module requires it — without that check, rotating a
secret plans clean and does nothing.

`data` is also *computed*, and that cuts two ways. For a `kubernetes.io/service-account-token` Secret
the API server populates it and the provider reads it back, so a Secret of that type has content it
was never given.

### ⚠️ Removing `data` does not empty the Secret

A computed attribute reads a null config as *keep what is already there*, so deleting the `data`
argument from a call site is not a deletion. It is a no-op, and the content stays in the cluster.
MEASURED against state holding one key, with `terraform plan -refresh=false`:

```
data omitted   ->  no change to data; the key is still there
data = {}      ->  CHANGED data  {'password': ...} -> {}
```

So `data = {}` is what clears a Secret, not removing the argument. `binary_data` is not computed and
clears on removal like an ordinary attribute.

## ⚠️ Adopting an existing Secret: move state, don't import

`wait_for_service_account_token` is a provider *behaviour* flag, not a field on the object, so
`terraform import` cannot read it back — it lands as null, the configuration resolves it to the
provider's default of `true`, and the very next plan wants an in-place update.

MEASURED against a live Secret: importing produced

```
~ resource "kubernetes_secret_v1" "this" {
  + wait_for_service_account_token = true
```

with every other attribute unchanged. Setting the input explicitly does not help — the *before* side
is still null.

Adopting a Secret that another configuration already manages should therefore use `state mv`, which
carries the stored value across and plans clean. Where an import is genuinely the only option, expect
that one-time update; it changes nothing in the cluster for any Secret that is not a
`kubernetes.io/service-account-token`.

The namespace module has no equivalent trap: `wait_for_default_service_account` defaults to `false`,
which is also what an import produces, so the two agree.

## ⚠️ `type` is required because it is immutable

`kubernetes-res-secret` takes `type` as a **required** input with no default, which is a deliberate
break from the usual "omit it and let the provider decide" pattern.

Secret `type` is immutable in Kubernetes: changing it forces a delete-and-recreate. Left optional, an
omitted `type` resolves to `Opaque` — so adopting an existing `kubernetes.io/tls` Secret would plan a
replace. MEASURED against a live cert-manager Secret, with the module's defaults:

```
ACTIONS: ['delete', 'create']    replace_paths: [['type']]
  type   : 'kubernetes.io/tls' -> 'Opaque'
  data   : <2 keys> -> None
  labels : {controller.cert-manager.io/fao: true} -> None
```

That destroys the certificate and every `cert-manager.io/*` annotation with it. Requiring `type`
turns a silent destroy into a missing-argument error.

## Labels and annotations are authoritative

Both inputs default to `{}`, and Terraform manages them declaratively — so metadata present on an
existing object but absent from the call site is **removed**. That is correct behaviour and it is
also the second half of the trap above: adopting a cert-manager Secret without carrying over its one
label and eight `cert-manager.io/*` annotations strips them.

When adopting anything a controller also writes to, read the live object first and carry its metadata
into the call site. A faithful adoption plans as a plain `update` with `replace_paths: None`.

## `data` and `data_wo` are mutually exclusive

The provider enforces this itself with a clear message, so the module adds no validation of its own:

```
Error: Conflicting configuration arguments
"data_wo": conflicts with data
```

## `type` is not validated

Kubernetes accepts arbitrary custom Secret types alongside the well-known ones, so a `contains(...)`
list here would reject working configurations. The module takes whatever it is handed. See
[Conventions](../conventions.md#validation).

## Identity federation is labels and annotations, nothing more

`kubernetes-res-serviceaccount` carries no cloud-specific inputs. Azure workload identity, GCP
Workload Identity and EKS IRSA are all configured through ordinary metadata, so they go in `labels`
and `annotations` and the module stays free of any one cloud's vocabulary.

For Azure workload identity that means **both** of these, not either:

```hcl
labels = {
  "azure.workload.identity/use" = "true"
}

annotations = {
  "azure.workload.identity/client-id" = module.identity.client_id
}
```

The label opts pods using the account into the mutating webhook; the annotation names the identity.
The label alone injects nothing, and the annotation alone is never read — a workload that fails to
get a token has usually lost one of the pair.

## `default_secret_name` is not exposed

The provider still has the attribute and marks it **deprecated**, so surfacing it emits a warning on
every consumer's `terraform validate`. It would also be blank: Kubernetes 1.24 stopped auto-creating
the token Secret it named. Use the TokenRequest API, or a hand-made
`kubernetes.io/service-account-token` Secret, for a token you can actually read.

Confirmed against a live account — its stored `default_secret_name` is `''`.

## Adopting a ServiceAccount imports cleanly

Unlike the Secret module, `import` is fine here. MEASURED against a live account carrying workload
identity metadata: importing and planning with `automount_service_account_token` left null gives

```
ACTIONS: ['no-op']
```

`automount_service_account_token` is a real field on the object, so the provider reads it back —
there is no equivalent of the Secret module's `wait_for_service_account_token` artifact.

⚠️ One address detail when adopting from a `for_each` module: the old address carries the map key
(`kubernetes_service_account_v1.this["service"]`) and this module has none, so the move is
`state mv 'kubernetes_service_account_v1.this["service"]' kubernetes_service_account_v1.this`.

## `generate_name` is deliberately not exposed

The provider offers a server-assigned random suffix on all three resources. None of these modules
exposes it, for the same reason: a name that only exists after apply cannot be referenced by whatever
depends on it. A namespace is created ahead of a workload so the workload can name it, a Secret so a
pod can mount it, a ServiceAccount so a pod spec can set `serviceAccountName`. All three take `name`
and nothing else.
