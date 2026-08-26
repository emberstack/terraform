# =============================================================================
# KUBERNETES MANIFEST
# =============================================================================
# One Kubernetes object of any kind, given as a manifest. For custom resources
# and anything the provider has no first-class resource for.
#
# ⚠️ This resource needs API access at PLAN time. The provider fetches the
# OpenAPI schema for the manifest's `kind` to build its type, so the cluster has
# to be reachable to plan at all — it cannot be created in the same apply as the
# cluster.
#
# ⚠️ A CRD must already exist before a custom resource of that kind can even be
# PLANNED. Terraform cannot apply a CRD and a CR of it in one run: at plan time
# the kind is absent from the OpenAPI document and the plan fails outright. Order
# the CRD into an earlier unit — for a Helm chart that installs its own CRDs,
# that means depending on the release rather than sitting beside it.
#
# `manifest` is typed `any` rather than a map or an object. Terraform unifies map
# element types, and two manifests of different kinds have no common base type,
# so any narrower constraint would reject valid input. The cost is that a
# malformed manifest is caught by the API server rather than by a type check —
# the validations below cover only the three fields every object must carry.
#
# Deliberately not exposed: `wait_for`, which the provider marks deprecated in
# favour of the `wait` block below.
# =============================================================================

resource "kubernetes_manifest" "this" {
  manifest        = var.manifest
  computed_fields = var.computed_fields

  dynamic "field_manager" {
    for_each = var.field_manager != null ? [1] : []

    content {
      name            = var.field_manager.name
      force_conflicts = var.field_manager.force_conflicts
    }
  }

  dynamic "wait" {
    for_each = var.wait != null ? [1] : []

    content {
      rollout = var.wait.rollout
      fields  = var.wait.fields

      dynamic "condition" {
        for_each = var.wait.condition != null ? var.wait.condition : []

        content {
          type   = condition.value.type
          status = condition.value.status
        }
      }
    }
  }

  dynamic "timeouts" {
    for_each = var.timeouts != null ? [1] : []

    content {
      create = var.timeouts.create
      update = var.timeouts.update
      delete = var.timeouts.delete
    }
  }
}
