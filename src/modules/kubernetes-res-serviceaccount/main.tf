# =============================================================================
# KUBERNETES SERVICE ACCOUNT
# =============================================================================
# A single ServiceAccount. Identity federation — Azure workload identity, GCP
# Workload Identity, IRSA on EKS — is configured entirely through `labels` and
# `annotations`, so it is the caller's business and this module stays free of
# any one cloud's conventions.
#
# For Azure workload identity that means BOTH of these, not either:
#
#   labels      = { "azure.workload.identity/use"       = "true" }
#   annotations = { "azure.workload.identity/client-id" = "<uai client id>" }
#
# The label opts pods using this account into the mutating webhook; the
# annotation names the identity. The label alone injects nothing, and the
# annotation alone is never read.
#
# `secrets` and `image_pull_secrets` are sets, matching the provider — order
# carries no meaning and cannot produce a perpetual diff.
#
# Deliberately not exposed: `default_secret_name`. The provider deprecates it
# and Kubernetes 1.24 stopped auto-creating the token Secret it named, so it
# reads empty on any current cluster — surfacing it would emit a deprecation
# warning on every consumer's `validate` in exchange for a blank string. Use
# the TokenRequest API, or a hand-made `kubernetes.io/service-account-token`
# Secret, for a token you can read.
#
# Deliberately not exposed: `generate_name`. An account whose name is only known
# after apply cannot be named by the pod spec that has to reference it.
# =============================================================================

resource "kubernetes_service_account_v1" "this" {
  automount_service_account_token = var.automount_service_account_token

  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = var.labels
    annotations = var.annotations
  }

  dynamic "secret" {
    for_each = var.secrets

    content {
      name = secret.value
    }
  }

  dynamic "image_pull_secret" {
    for_each = var.image_pull_secrets

    content {
      name = image_pull_secret.value
    }
  }

  dynamic "timeouts" {
    for_each = var.timeouts != null ? [1] : []

    content {
      create = var.timeouts.create
    }
  }
}
