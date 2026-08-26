# Helm

Modules on the `hashicorp/helm` provider.

## Modules

| Module | What it manages | Submodules |
|---|---|---|
| [`helm-res-release`](../../src/modules/helm-res-release/) | A single Helm release of any chart | — |

## The module shapes no chart

`helm-res-release` is deliberately chart-agnostic. It does not know what a `traefik` value looks like
and never will — values are written by the caller against the chart's own schema and passed straight
through.

That is a different bargain from a per-chart module. A `traefik` module can validate that
`ingressClass.name` is set; this one cannot. What it buys instead is that adopting a new chart costs a
call site rather than a module, and that a chart's own documentation reads as a valid call site.

## No default is invented here

**Every optional input defaults to `null`, so Helm's own default applies.** The module contributes
none of its own.

This is worth stating because the tempting alternative — defaulting `upgrade_install` to `true`, say,
because it is usually what you want — makes the module lie. Someone comparing a call site against
Helm's documentation would find behaviour that appears nowhere in either, and there is no way to opt
back out of a default that lives inside a module.

The consequence for callers is that anything non-default has to be asked for explicitly. `atomic`,
`upgrade_install` and `max_history` are the ones most often wanted and most often forgotten.

`wait` is not one of them, and it is the one worth knowing. MEASURED against provider v3.2, a release
with every optional input left null plans `wait = true` and `timeout = 300` — so an apply already
blocks on readiness for five minutes, and it is switching that *off* that has to be asked for.

## Values precedence

Six inputs feed chart values, and Helm merges them lowest-to-highest:

| Input | Equivalent |
|---|---|
| `values` | an HCL object rendered to YAML, passed as the first `-f` |
| `values_yaml` | raw YAML documents, passed as further `-f` arguments in order |
| `set`, `set_list` | `--set`, `--set-list` |
| `set_sensitive` | `--set` with the value kept out of plan output |
| `set_wo` | `--set` with the value kept out of state entirely |

`values` is typed `any` rather than `map(any)` or a `map` of objects. That is not laziness:

```
Error: Invalid value for input variable
all map elements must have the same type.
```

Terraform unifies map element types, and two chart values of different shapes have no common base
type. `any` passes the object through untouched. The same wall appears one level deeper — a
`map(object({ values = any }))` fails with *"cannot find a common base type for all elements"* — so
wrapping does not rescue it either.

## Where a secret ends up

Measured against provider v3.2:

| Input | Terraform state | Plan output |
|---|---|---|
| `values`, `values_yaml`, `set` | cleartext | cleartext |
| `set_sensitive` | cleartext | redacted |
| `set_wo` | **not written** | not shown |
| `repository_password` | cleartext | redacted |

`set_sensitive` is the one that misleads. It marks the value sensitive, which keeps it out of plan
output and CI logs — and writes it to state anyway. Only `set_wo`, a Terraform write-only attribute,
keeps a value out of the state file at all.

**`set_wo` costs drift detection.** Terraform cannot read a write-only value back, so it cannot notice
that one changed. `set_wo_revision` is what re-sends them, and the module requires it whenever
`set_wo` is used — without that check, rotating a secret plans clean and does nothing.

### None of this reaches Helm's own copy

Helm stores every revision — rendered manifests and merged values alike — in a Secret named
`sh.helm.release.v1.<name>.v<revision>` in the release namespace. Anyone who can read Secrets there
can read every value ever passed, whichever input carried it, and `helm get values` replays them.

That is Helm's behaviour, not the provider's, and no module input changes it. `set_wo` protects the
state file. It does not protect the cluster.

The `notes` output is marked sensitive for the same reason: charts that generate a password commonly
print it in `NOTES.txt`.

## Namespaces

**The module does not manage a namespace**, and that is what keeps it on a single provider. `namespace`
names the target; two ways to get one there:

| | `create_namespace = true` | [`kubernetes-res-namespace`](kubernetes.md) |
|---|---|---|
| Created by | Helm | Terraform |
| Labels and annotations | no | yes |
| Drift detected | no | yes |
| On destroy | left behind | **deleted, with everything in it** |
| Needs the kubernetes provider | no | yes |

`create_namespace` defaults to `false` — the one place this module states a default rather than
passing null, because it matches Helm's own and reads better than an empty knob.

Reach for the module when the namespace carries metadata — Pod Security Admission labels most often —
or should be removed along with what it holds. Reach for the flag when you just need somewhere for the
release to land. Where several releases share a namespace, neither release should own it: give the
namespace its own module and pass the `name` output to each, which also orders them behind it.

## OCI charts

Both forms work, and they are mutually exclusive:

```hcl
# repository + chart name
repository    = "oci://ghcr.io/emberstack/helm-charts"
chart         = "generic"

# full reference, no repository
chart         = "oci://ghcr.io/emberstack/helm-charts/generic"
```

`repository` is validated as an `http://`, `https://` or `oci://` URL when set. `chart` is not
pattern-validated, because it legitimately holds a chart name, an OCI reference or a local path.

## `version` is spelled `chart_version`

Terraform reserves `version` as a variable name for module block meta-arguments:

```
The variable name "version" is reserved due to its special meaning inside module blocks.
```

So the input is `chart_version`. It maps to `helm_release.version` and means exactly what it looks
like. Leaving it null resolves the latest version at apply time, which makes the release
irreproducible — pin it.
