# =============================================================================
# KUBERNETES SECRET
# =============================================================================
# A single Secret. Four inputs carry its content, and they are not
# interchangeable:
#
#   data             plaintext in, provider base64-encodes it
#   binary_data      ALREADY base64-encoded going in
#   data_wo          plaintext, write-only — never persisted to state
#   binary_data_wo   base64, write-only — never persisted to state
#
# ⚠️ Passing base64 to `data` double-encodes it. The Secret applies cleanly and
# the consuming pod reads gibberish, so the failure surfaces in the workload
# rather than here.
#
# ⚠️ `data` and `binary_data` are written to state in cleartext. The provider
# marks them sensitive, which keeps them out of plan output and CI logs — it
# does not encrypt state, and nothing at the module level can. Use the `_wo`
# variants for material that must not land in the state file at all; they cost
# drift detection, because Terraform cannot read a write-only value back to
# compare, and the matching `_wo_revision` is what re-sends them.
#
# `data` is also computed, and that cuts two ways. For a
# `kubernetes.io/service-account-token` Secret the API server populates it, and
# the provider reads that back. But a computed attribute reads a null config as
# "keep what is already there" — so REMOVING `data` from a call site does not
# empty the Secret. MEASURED: the plan reports no change to `data` and the
# content stays in the cluster. Pass `data = {}` to clear it. `binary_data` is
# not computed and clears on removal.
#
# Deliberately not exposed: `generate_name`. A Secret whose name is only known
# after apply cannot be referenced by the workload that mounts it.
# =============================================================================

resource "kubernetes_secret_v1" "this" {
  type      = var.type
  immutable = var.immutable

  data           = var.data
  binary_data    = var.binary_data
  data_wo        = var.data_wo
  binary_data_wo = var.binary_data_wo

  data_wo_revision        = var.data_wo_revision
  binary_data_wo_revision = var.binary_data_wo_revision

  wait_for_service_account_token = var.wait_for_service_account_token

  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = var.labels
    annotations = var.annotations
  }

  dynamic "timeouts" {
    for_each = var.timeouts != null ? [1] : []

    content {
      create = var.timeouts.create
    }
  }
}
