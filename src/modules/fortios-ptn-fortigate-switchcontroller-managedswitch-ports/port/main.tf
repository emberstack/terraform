# =============================================================================
# Single FortiSwitch port — managed via the per-port child mkey REST path.
# =============================================================================
# Only fields explicitly set in the leaf are sent. FortiOS PUT to the per-port
# path merges, so unset/hardware/computed fields are left untouched — no
# nulling, no positional churn. The restful_resource reads the port each plan
# (read_selector pulls it out of the FortiOS {results:[...]} envelope), giving
# native two-way drift detection scoped to just the fields in `body`.
# =============================================================================

locals {
  # Build the request body from only the fields that are actually set, so a
  # null/omitted leaf field never overwrites box state with an empty value.
  body = merge(
    { status = var.status },
    var.vlan != null ? { vlan = var.vlan } : {},
    var.poe_status != null ? { "poe-status" = var.poe_status } : {},
    var.description != null ? { description = var.description } : {},
    var.port_security_policy != null ? { "port-security-policy" = var.port_security_policy } : {},
    var.allowed_vlans_all != null ? { "allowed-vlans-all" = var.allowed_vlans_all } : {},
    length(var.allowed_vlans) > 0 ? { "allowed-vlans" = [for v in var.allowed_vlans : { "vlan-name" = v }] } : {},
    length(var.untagged_vlans) > 0 ? { "untagged-vlans" = [for v in var.untagged_vlans : { "vlan-name" = v }] } : {},
  )
}

resource "restful_resource" "this" {
  # Per-port child mkey path. FortiOS treats <port_name> as the sub-resource id.
  path = "/cmdb/switch-controller/managed-switch/${var.switch_id}/ports/${var.port_name}"

  # Port already exists physically; "create" adopts it via PUT rather than POST.
  create_method = "PUT"
  update_method = "PUT"

  # FortiOS wraps single-object reads as { "results": [ { ...port... } ], ... }.
  # Select the first (only) element so drift compares against the port object.
  read_selector = "results.0"

  # Physical ports can't be DELETE'd — on destroy, revert to a safe default
  # (access VLAN _default) instead of issuing a DELETE FortiOS would reject.
  delete_method = "PUT"
  delete_body = {
    vlan = "_default"
  }

  body = local.body
}
