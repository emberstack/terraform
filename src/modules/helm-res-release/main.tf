# =============================================================================
# HELM RELEASE
# =============================================================================
# A single Helm release of any chart. The module shapes no chart in particular —
# values are written by the caller against the chart's own schema.
#
# The namespace is not managed here. `create_namespace` asks Helm for a bare one;
# a namespace carrying labels, annotations or a lifecycle of its own belongs to
# `kubernetes-res-namespace`, which is also what keeps this module on a single
# provider.
#
# Every optional input defaults to null, so Helm's own default applies and this
# module contributes none of its own. A library that quietly flips a Helm default
# reads as a bug the first time someone compares a call site against the chart's
# documentation, and there is no way to opt back out of a default that lives in
# the module.
#
# Where secret material ends up, measured against provider v3.2:
#
#   values, values_yaml, set  cleartext in state, cleartext in plan output
#   set_sensitive             cleartext in state, redacted in plan output
#   set_wo                    never written to state, never shown
#
# So `set_wo` is the only input that keeps a secret out of the state file. It
# costs drift detection: Terraform cannot read a write-only value back, so it
# cannot tell that one changed, and `set_wo_revision` is what re-sends it.
#
# None of that reaches Helm's own copy. Helm stores each revision — rendered
# manifests and merged values alike — in a Secret named
# `sh.helm.release.v1.<name>.v<revision>` in the release namespace. Anyone who
# can read Secrets there can read every value ever passed, whichever input
# carried it.
# =============================================================================

# -----------------------------------------------------------------------------
# Values
# -----------------------------------------------------------------------------

locals {
  # `values` is rendered first so `values_yaml` overrides it, matching the
  # left-to-right precedence of repeated `helm -f` arguments. An empty object
  # contributes nothing rather than an empty YAML document, which keeps the
  # rendered list — and the plan diff — to exactly what the caller supplied.
  values = concat(
    var.values != null && length(var.values) > 0 ? [yamlencode(var.values)] : [],
    var.values_yaml,
  )
}

# -----------------------------------------------------------------------------
# Release
# -----------------------------------------------------------------------------

resource "helm_release" "this" {
  name = var.name

  namespace = var.namespace

  chart               = var.chart
  repository          = var.repository
  version             = var.chart_version
  devel               = var.devel
  verify              = var.verify
  keyring             = var.keyring
  repository_username = var.repository_username
  repository_password = var.repository_password

  repository_ca_file   = var.repository_ca_file
  repository_cert_file = var.repository_cert_file
  repository_key_file  = var.repository_key_file
  pass_credentials     = var.pass_credentials

  values          = local.values
  set             = var.set
  set_list        = var.set_list
  set_sensitive   = var.set_sensitive
  set_wo          = var.set_wo
  set_wo_revision = var.set_wo_revision

  create_namespace = var.create_namespace
  upgrade_install  = var.upgrade_install
  atomic           = var.atomic
  cleanup_on_fail  = var.cleanup_on_fail
  wait             = var.wait
  wait_for_jobs    = var.wait_for_jobs
  timeout          = var.timeout
  max_history      = var.max_history
  replace          = var.replace
  force_update     = var.force_update
  recreate_pods    = var.recreate_pods
  reset_values     = var.reset_values
  reuse_values     = var.reuse_values
  take_ownership   = var.take_ownership
  description      = var.description

  skip_crds                  = var.skip_crds
  disable_crd_hooks          = var.disable_crd_hooks
  disable_webhooks           = var.disable_webhooks
  disable_openapi_validation = var.disable_openapi_validation
  dependency_update          = var.dependency_update
  lint                       = var.lint
  render_subchart_notes      = var.render_subchart_notes

  postrender = var.postrender
  timeouts   = var.timeouts
}
