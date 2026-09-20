# =============================================================================
# AGENT POOL (Microsoft.ContainerService/managedClusters/agentPools)
# =============================================================================
# A pool as its own ARM child resource, so it can be added, rolled and removed
# without rewriting the cluster. The parent module's `default_node_pool` seeds
# the cluster's create body and is not manageable this way; everything else is.
#
# `locks` on the cluster serialises every pool against the cluster and against
# each other. AKS runs one operation on a cluster at a time and fails the rest
# with a conflict, so parallel pool writes — which is what Terraform does by
# default with a `for_each` — would fail on all but the first. It also orders
# the two halves of a create-before-destroy replacement.
#
# `vmSize` is the one immutable property worth replacing a pool over: a pool is
# a scale set, and replacing one is routine where replacing a cluster is not.
# The rest of the create-only set is left to ARM to reject by name, rather than
# quietly rebuilt.
#
# The pool is declared twice because `create_before_destroy` cannot be set from
# a variable. The two are mutually exclusive on `count` and share one body; the
# create-before-destroy copy carries a generated name, because the replacement
# has to exist alongside the pool it replaces and ARM will not have two of the
# same name on one cluster.
# =============================================================================

locals {
  api_version = "Microsoft.ContainerService/managedClusters/agentPools@2025-09-02-preview"

  # Sent only when the autoscaler is off. With it on, the running size is the
  # autoscaler's to decide, and omitting the property — `ignore_null_property`
  # drops the null — means it is neither written nor compared, so a scaled-out
  # pool is never dragged back on the next apply. Leaving it out is what makes
  # `node_count` reconcilable in the mode where it means something, rather than
  # ignored in both. AKS starts an autoscaling pool at `minCount`.
  managed_count = var.auto_scaling.enabled ? null : var.node_count

  # Optional groups are written as nulls in one flat body rather than merged in
  # as whole objects. A conditional between `{}` and a populated object unifies
  # the two sides to a single map type, and a map has one element type: an
  # object mixing a string and a number comes back as map(string), and
  # `spotMaxPrice` reaches ARM quoted. `ignore_null_property` drops the nulls
  # instead.
  body = {
    properties = {
      type                   = "VirtualMachineScaleSets"
      mode                   = var.mode
      osType                 = var.os_type
      osSKU                  = var.os_sku
      vmSize                 = var.vm_size
      osDiskSizeGB           = var.os_disk_size_gb
      osDiskType             = var.os_disk_type
      kubeletDiskType        = var.kubelet_disk_type
      maxPods                = var.max_pods
      enableEncryptionAtHost = var.host_encryption_enabled
      enableFIPS             = var.fips_enabled
      enableNodePublicIP     = var.node_public_ip_enabled
      availabilityZones      = var.zones
      vnetSubnetID           = var.vnet_subnet_resource_id
      podSubnetID            = var.pod_subnet_resource_id
      nodeLabels             = var.node_labels
      nodeTaints             = var.node_taints
      orchestratorVersion    = var.orchestrator_version
      scaleDownMode          = var.scale_down_mode
      enableAutoScaling      = var.auto_scaling.enabled
      count                  = local.managed_count
      minCount               = var.auto_scaling.enabled ? var.auto_scaling.min_count : null
      maxCount               = var.auto_scaling.enabled ? var.auto_scaling.max_count : null
      scaleSetPriority       = var.spot == null ? null : "Spot"
      scaleSetEvictionPolicy = try(var.spot.eviction_policy, null)
      spotMaxPrice           = try(var.spot.max_price, null)
      upgradeSettings = {
        maxSurge                  = var.upgrade_settings.max_surge
        drainTimeoutInMinutes     = var.upgrade_settings.drain_timeout_in_minutes
        nodeSoakDurationInMinutes = var.upgrade_settings.node_soak_duration_in_minutes
      }
      # ARM's own field name and polarity, not the inverted one every SDK
      # exposes. Null stays null — unset and "NAT enabled" are different states.
      windowsProfile = var.windows_outbound_nat_enabled == null ? null : {
        disableOutboundNat = !var.windows_outbound_nat_enabled
      }
      # On an agent pool, tags is a PROPERTY. It is not the body-level `tags` the
      # rest of ARM uses, and AzAPI's schema rejects it there.
      tags = var.tags
    }
  }
}

# -----------------------------------------------------------------------------
# Pool
# -----------------------------------------------------------------------------

resource "azapi_resource" "this" {
  count = var.create_before_destroy ? 0 : 1

  name                 = var.name
  parent_id            = var.cluster_resource_id
  type                 = local.api_version
  body                 = local.body
  ignore_null_property = true
  locks                = [var.cluster_resource_id]
  replace_triggers_refs = [
    "properties.vmSize",
  ]
  response_export_values = {
    provisioning_state           = "properties.provisioningState"
    current_orchestrator_version = "properties.currentOrchestratorVersion"
    node_image_version           = "properties.nodeImageVersion"
  }

  timeouts {
    create = var.timeouts.create
    read   = var.timeouts.read
    update = var.timeouts.update
    delete = var.timeouts.delete
  }
}

# -----------------------------------------------------------------------------
# Pool, replaced without a capacity gap
# -----------------------------------------------------------------------------
# Identical but for the name and the lifecycle. `uuid()` is re-evaluated on
# every plan, so the generated name is ignored once the pool exists — which in
# turn means a change to `var.name` would go unnoticed, and the keeper below
# exists to make it a replacement again.

# Deliberately not gated on `create_before_destroy`. It costs nothing — no API
# call, one state entry — and keeping it unconditional means the reference in
# the lifecycle block below can never index an empty list.
resource "terraform_data" "name" {
  triggers_replace = var.name
}

resource "azapi_resource" "this_create_before_destroy" {
  count = var.create_before_destroy ? 1 : 0

  name                 = "${var.name}${substr(sha256(uuid()), 0, 4)}"
  parent_id            = var.cluster_resource_id
  type                 = local.api_version
  body                 = local.body
  ignore_null_property = true
  locks                = [var.cluster_resource_id]
  replace_triggers_refs = [
    "properties.vmSize",
  ]
  response_export_values = {
    provisioning_state           = "properties.provisioningState"
    current_orchestrator_version = "properties.currentOrchestratorVersion"
    node_image_version           = "properties.nodeImageVersion"
  }

  timeouts {
    create = var.timeouts.create
    read   = var.timeouts.read
    update = var.timeouts.update
    delete = var.timeouts.delete
  }

  lifecycle {
    create_before_destroy = true
    # `uuid()` is re-evaluated on every plan, so the generated name has to be
    # frozen once the pool exists. Nothing else is ignored here.
    ignore_changes       = [name]
    replace_triggered_by = [terraform_data.name]
  }
}

locals {
  # Exactly one of the two exists. `concat` over the count lists avoids naming
  # either index directly, which would fail on whichever is empty.
  pool = one(concat(azapi_resource.this, azapi_resource.this_create_before_destroy))
}
