# =============================================================================
# One-off pattern: hide the FortiConverter login prompt
# =============================================================================
# Single-purpose, NOT parameterized. A cli-script automation action runs the
# diag command; a stitch fires it on the built-in "Reboot" trigger (we
# reference it, never redefine it). The diag setting is non-persistent, so
# re-running on every reboot keeps the prompt hidden permanently.
#
# Why a cli-script automation: the REST cmdb API has no generic CLI passthrough,
# but a cli-script action IS a cmdb object — so this is the supported way to
# run a `diagnose` command declaratively, drift-tracked.
#
# NOTE: the leaf must use the OPERATOR API token for ALL commands (incl. plan),
# because the FortiGate's reader admin profile cannot read system/automation-*
# objects (FortiOS returns 404), which would make plan see phantom drift.
# =============================================================================

resource "fortios_system_automationaction" "this" {
  name        = var.action_name
  description = "Hide the FortiConverter login prompt (runs on reboot)."
  action_type = "cli-script"
  script      = "diagnose sys forticonverter set-prompt-visibility hidden"
  accprofile  = "super_admin"
}

resource "fortios_system_automationstitch" "this" {
  name        = var.stitch_name
  description = "Hide the FortiConverter login prompt (runs on reboot)."
  status      = "enable"
  trigger     = "Reboot" # built-in FortiOS trigger (event-type=reboot)

  actions {
    id     = 1
    action = fortios_system_automationaction.this.name
  }
}
