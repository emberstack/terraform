# =============================================================================
# KUBERNETES NAMESPACE
# =============================================================================
# A single namespace, owned by Terraform: labels and annotations are managed,
# drift is detected, and the namespace is removed when the module is.
#
# ⚠️ Destroying this destroys everything inside it. A namespace delete is
# recursive and unconditional — workloads, Secrets, PVCs, anything reflected in
# from elsewhere. Terraform plans it as one line. Point this module only at a
# namespace whose whole contents you are willing to lose with it.
#
# Deleting a namespace also blocks on finalizers, and a resource whose finalizer
# never clears leaves it Terminating indefinitely. `timeouts.delete` bounds the
# wait so a stuck namespace fails the apply instead of hanging it — the
# namespace still needs unwedging by hand afterwards.
#
# Deliberately not exposed: `generate_name`. A namespace with a server-assigned
# random suffix cannot be named by whatever installs into it, which is the whole
# reason a namespace is created ahead of a workload.
# =============================================================================

resource "kubernetes_namespace_v1" "this" {
  wait_for_default_service_account = var.wait_for_default_service_account

  metadata {
    name        = var.name
    labels      = var.labels
    annotations = var.annotations
  }

  dynamic "timeouts" {
    for_each = var.timeouts != null ? [1] : []

    content {
      delete = var.timeouts.delete
    }
  }
}
