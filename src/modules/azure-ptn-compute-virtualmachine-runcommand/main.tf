# =============================================================================
# VM RUN COMMAND (Microsoft.Compute/virtualMachines/runCommands)
# =============================================================================
# Runs one script inside a virtual machine this module does not own, from any of
# the three sources ARM accepts: inline script text, a downloadable script URI,
# or the commandId of a script Azure already ships (EnableRemotePS, DisableNLA,
# IPConfig, RDPSettings, ...). Exactly one of them, enforced in variables.tf,
# because ARM supports only one source input per execution.
#
# A managed run command, not a CustomScriptExtension: CustomScript is limited to
# one instance per VM, so a module that claims that slot locks its caller out of
# the VM's only general-purpose script channel, permanently. Run commands are
# named child resources — a VM carries as many as it needs.
#
# Two defaults deliberately differ from ARM's, in the safe direction:
#
#   - treatFailureAsDeploymentFailure defaults to TRUE here; ARM defaults it to
#     false. Under ARM's default provisioningState reports only whether the
#     handler managed to START the script, so a script that throws still applies
#     clean. A module whose whole job is running a script should fail when the
#     script fails.
#   - asyncExecution defaults to FALSE, so the PUT completes only once the
#     script has finished. That is what makes the failure default meaningful,
#     and what lets the optional restart below land strictly after the script.
#
# Ordering is the caller's depends_on. Run commands carry no
# provisionAfterExtensions, and several deployed together execute in PARALLEL by
# default — sequencing them is the consumer's job, exactly as in an ARM template.
#
# Re-run semantics: the script executes on create, and on any update to this
# resource. ARM has no "run it again" verb, so re-running unchanged content
# means a new resource — change `name`.
#
# A run command is a child resource: replacing the VM deletes it in ARM while
# the name-based resource ID Terraform tracks stays identical, so that same
# apply plans no change here and the rebuilt VM never runs the script. The next
# plan reads a 404, drops the state entry and recreates it — expect a one-apply
# gap after any VM replacement.
#
# Removing this module unregisters the run command, terminating it if it is
# still executing. It does not undo whatever the script already did.
#
# Pinned to API 2024-07-01. `scriptShell` (PowerShell 7) and
# `galleryScriptReferenceId` arrived in 2025-04-01 and are deliberately out of
# scope; adding either means moving the pin for every consumer.
# =============================================================================

locals {
  # Built by merge rather than a three-way conditional: the branches carry
  # different attribute names, and merging single-key maps keeps the result one
  # consistent type. An absent source is omitted from the body entirely rather
  # than sent as null, which ARM would read as a second source being supplied.
  source = merge(
    var.script != null ? { script = var.script } : {},
    var.script_uri != null ? { scriptUri = var.script_uri } : {},
    var.command_id != null ? { commandId = var.command_id } : {},
  )

  # ARM wants an ordered [{name, value}] array. The inputs are maps keyed by
  # parameter name and `for` over a map iterates in lexical key order, so the
  # array is deterministic across runs — no spurious diffs from reordering.
  # Order is immaterial on Windows, where parameters arrive as named arguments
  # (`-name value`); see the Linux note in variables.tf.
  parameters           = [for name, value in var.parameters : { name = name, value = value }]
  protected_parameters = [for name, value in var.protected_parameters : { name = name, value = value }]

  # Optional properties are merged in only when set, so an unset one is absent
  # from the request rather than an explicit null. That matters for
  # timeoutInSeconds and runAsUser, where ARM's own default is the intent.
  properties = merge(
    {
      source                          = local.source
      asyncExecution                  = var.async_execution
      treatFailureAsDeploymentFailure = var.treat_failure_as_deployment_failure
    },
    length(local.parameters) > 0 ? { parameters = local.parameters } : {},
    length(local.protected_parameters) > 0 ? { protectedParameters = local.protected_parameters } : {},
    var.timeout_in_seconds != null ? { timeoutInSeconds = var.timeout_in_seconds } : {},
    var.run_as_user != null ? { runAsUser = var.run_as_user } : {},
    var.run_as_password != null ? { runAsPassword = var.run_as_password } : {},
    var.output_blob_uri != null ? { outputBlobUri = var.output_blob_uri } : {},
    var.error_blob_uri != null ? { errorBlobUri = var.error_blob_uri } : {},
  )
}

# -----------------------------------------------------------------------------
# The run command
# -----------------------------------------------------------------------------

resource "azapi_resource" "run_command" {
  type      = "Microsoft.Compute/virtualMachines/runCommands@2024-07-01"
  name      = var.name
  parent_id = var.virtual_machine_id
  location  = var.location
  tags      = var.tags

  body = {
    properties = local.properties
  }

  # protectedParameters, runAsPassword and the two blob SAS URIs are write-only:
  # ARM accepts them and never reads them back, so without this every plan shows
  # a diff for a value that is already set. Stated explicitly even though the
  # provider defaults it true, because the module deliberately sends secrets in
  # `body` and a reader needs to see the diff suppression that implies.
  #
  # `sensitive_body` would keep those values out of state entirely and is the
  # stronger option, but it is version-gated: a path whose
  # `sensitive_body_version` has not changed is OMITTED from the request, and
  # against a full-replace write that risks clearing a secret on an unrelated
  # update. Adopting it needs an apply test first.
  ignore_missing_property = true

  response_export_values = ["properties.provisioningState"]

  retry = var.retry

  # Terraform's own operation deadline, not the script's. It has to outlast
  # timeoutInSeconds — 90 minutes by default, and managed run commands allow
  # far longer — or Terraform gives up while the script is still running.
  timeouts {
    create = var.timeouts.create
    update = var.timeouts.update
    delete = var.timeouts.delete
  }
}

# -----------------------------------------------------------------------------
# Optional restart, so a script whose effect needs a reboot actually takes hold
# -----------------------------------------------------------------------------
# An ARM restart, not an in-guest `shutdown`: an in-guest reboot is invisible to
# ARM, so Terraform cannot wait on it. Several built-in commands need one —
# DisableNLA documents that the script itself does not restart the VM.
#
# replace_triggered_by keys on the run command's body, which carries the script
# and its parameters, so the restart re-fires exactly when what ran changed.
# Name and tags are separate top-level attributes and do not re-fire it.

resource "azapi_resource_action" "reboot" {
  count = var.reboot ? 1 : 0

  type        = "Microsoft.Compute/virtualMachines@2024-07-01"
  resource_id = var.virtual_machine_id
  action      = "restart"
  method      = "POST"

  retry = var.retry

  timeouts {
    create = var.reboot_timeout
  }

  lifecycle {
    replace_triggered_by = [azapi_resource.run_command.body]
  }

  depends_on = [azapi_resource.run_command]
}
