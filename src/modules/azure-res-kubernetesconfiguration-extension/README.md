# Kubernetes cluster extension

Terraform module for a **cluster extension** (`Microsoft.KubernetesConfiguration/extensions`) — the ARM resource behind `az k8s-extension create`.

The parent is a cluster resource ID, so one module covers every cluster resource provider the extensions RP accepts: AKS (`Microsoft.ContainerService/managedClusters`), Arc (`Microsoft.Kubernetes/connectedClusters`), AKS hybrid (`Microsoft.HybridContainerService/provisionedClusters`) and `Microsoft.ResourceConnector/appliances`.

## Why this exists

There is no Terraform AVM module for this resource — AVM ships `avm/res/kubernetes-configuration/extension` in Bicep only, and `Azure/avm-res-containerservice-managedcluster/azurerm` covers `addonProfiles`, which are a different thing. `azurerm_kubernetes_cluster_extension` exists but lags the API version and has no write-only handling for protected settings.

**Extensions are not addons.** `azurepolicy`, `omsagent`, `ingress-appgw` and `open-service-mesh` live in the managed cluster's own `addonProfiles`, not here. Installing one of those means updating the cluster resource, not creating an extension.

## Usage

### Minimal

```hcl
module "flux" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-kubernetesconfiguration-extension?ref=vX.Y.Z"

  name                = "flux"
  cluster_resource_id = var.aks_cluster_resource_id
  extension_type      = "microsoft.flux"
}
```

### Pinned version, no auto-upgrade

`extension_version` and `auto_upgrade_minor_version` are mutually exclusive — ARM only honours a pinned version while auto-upgrade is off, and a variable validation enforces it.

```hcl
module "flux" {
  source = "..."

  name                       = "flux"
  cluster_resource_id        = var.aks_cluster_resource_id
  extension_type             = "microsoft.flux"
  auto_upgrade_minor_version = false
  extension_version          = "1.14.1"
}
```

### Scope and configuration settings

`configuration_settings` is a flat `map(string)` because that is what the ARM contract is — the keys are the extension's own, published by the extension rather than by ARM.

```hcl
module "app_configuration" {
  source = "..."

  name                = "app-configuration"
  cluster_resource_id = var.aks_cluster_resource_id
  extension_type      = "Microsoft.AppConfiguration"

  scope = {
    kind      = "cluster"
    namespace = "kube-cluster-app-configuration"
  }

  configuration_settings = {
    replicaCount = "2"
  }
}
```

Swap the scope for a per-namespace instance where the extension type supports one — `microsoft.flux`, for example, does not:

```hcl
  scope = {
    kind      = "namespace"
    namespace = "my-namespace"
  }
```

### Protected settings

Protected settings are write-only — ARM never returns them, so Terraform cannot see that they changed. Bump `configuration_protected_settings_version` to push a new value.

```hcl
module "extension" {
  source = "..."

  # ...

  configuration_protected_settings = {
    "connection.token" = var.token
  }
  configuration_protected_settings_version = "2" # bumped when the token rotated
}
```

### Granting the extension's identity rights

```hcl
module "extension" {
  source = "..."

  # ...

  identity_role_assignments = {
    acr_pull = {
      role_definition_id_or_name = "AcrPull"
      scope                      = var.container_registry_resource_id
    }
  }
}
```

The principal is the AKS-assigned identity where the resource provider creates one, otherwise the extension's own system-assigned identity (`managed_identities = { system_assigned = true }`). Both are unknown until apply; an extension with neither fails a precondition instead of sending a null principal to ARM.

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Notes

### What is immutable

`Extensions_Update` (PATCH) in the `2025-03-01` spec accepts exactly six properties: `autoUpgradeMinorVersion`, `autoUpgradeMode`, `releaseTrain`, `version`, `configurationSettings`, `configurationProtectedSettings`. Everything else is create-only.

AzAPI writes with PUT, which ARM accepts without re-installing anything, so changing `extension_type`, `scope`, `managed_identities`, `plan` or `cluster_resource_id` would leave the old chart running while state claimed otherwise. Those five are listed in `replace_triggers_external_values` and force a replacement instead.

### Interfaces this module does not have

| Absent | Why |
|---|---|
| `tags`, `location` | The resource is a ProxyResource — ARM has nowhere to store either |
| `diagnostic_settings` | The resource type publishes no log or metric categories |
| Resource-scoped `role_assignments` | Rights over an extension instance are not something callers grant; rights *for* its identity are, and those are `identity_role_assignments` |
| `user_assigned_resource_ids` | The resource types its `identity` as the v3 common-types `Identity`, whose only accepted value is `SystemAssigned` |

### Settings the resource provider rewrites

`ignore_null_property` covers the properties this module sends as null and ARM materialises a default for. It does **not** cover a key inside `configuration_settings` that the extension agent writes back with a different value — that is a permanent diff, and the fix is to stop sending the key. There is no per-key ignore input; add one when a real extension needs it.

### Stuck destroys

ARM's normal delete waits for the extension agent to uninstall the release in the cluster, and never returns when the release is wedged or the cluster is unreachable. `force_delete = true` sends ARM's `forceDelete` query parameter, which drops the ARM resource without that handshake — **leaving the in-cluster objects behind**. Use it to break a stuck destroy, then clean the cluster by hand before re-installing the same extension type.

### Prerequisites

`Microsoft.KubernetesConfiguration` must be registered on the subscription, and a marketplace extension needs its offer terms accepted, before the PUT will succeed. Neither is done by this module.
