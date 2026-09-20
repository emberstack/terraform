# =============================================================================
# MANAGED CLUSTER (Microsoft.ContainerService/managedClusters)
# =============================================================================
# The cluster and nothing that runs inside it. Extensions, Flux configurations
# and Helm releases are separate modules; this one owns the ARM resource, its
# system node pool, and the interfaces every `res` module carries.
#
# Two properties are deliberately not reconciled after creation:
#
#   agentPoolProfiles  An ARM write is a full replace, so a PUT carrying only the
#                      system pool would strip every pool the `agentpool`
#                      submodule owns. The profile list seeds the create call and
#                      ownership passes to the child resources immediately after.
#                      The cluster autoscaler moves `count` as well, which nothing
#                      in Terraform should be arguing with.
#
#   kubernetesVersion  An upgrade channel other than `none` moves it server-side.
#                      Reconciling it here would drag the cluster back to the
#                      configured version on the next apply — so the input is
#                      applied by a separate, serialised call instead.
#
# There are no `replace_triggers_refs`. Several properties are genuinely
# create-only, but on a managed cluster a plan-time "replace" is the deletion of
# a running cluster, and ARM rejects each of those changes on its own with an
# error that names the property. A loud failure beats a silent rebuild.
#
# The API version is pinned to a preview one because two supported features need
# it: `ingressProfile.applicationLoadBalancer` and the KMS
# `kubernetesResourceObjectEncryptionProfile`. Neither has reached a stable
# version yet; when both do, this is the only line that changes.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # ARM stamps `retentionPolicy` onto every log and metric entry it returns,
  # years after retention moved to the workspace. azapi compares arrays
  # wholesale rather than per-property, so one entry missing it - or one
  # category ARM materialised that the config never sent - makes the whole
  # diagnostic setting diff on every plan, forever.
  diagnostic_retention_policy = { days = 0, enabled = false }

  # The subscription the provider is configured against. Used to list the
  # roleDefinitions catalogue. Built-in roles are present in every subscription,
  # so this resolves any built-in name; a CUSTOM role defined in a different
  # subscription is not in this listing and must be passed as a resource ID.
  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"

  # The input stays a plain resource group name (AVM's shape); the subscription
  # comes from the configured provider, so an aliased or multi-subscription
  # caller still lands in the right place.
  resource_group_resource_id = "${local.provider_subscription_resource_id}/resourceGroups/${var.resource_group_name}"

  api_version = "Microsoft.ContainerService/managedClusters@2025-09-02-preview"

  # AKS takes one or the other, never both, which the variable's validation
  # enforces — so this is a two-way choice rather than the four-way one the
  # generic AVM identity interface models.
  identity_type = var.managed_identities.system_assigned ? "SystemAssigned" : "UserAssigned"
}

locals {
  # `count` is the pool's initial size. With the autoscaler on it is seeded from
  # min_count and owned by the autoscaler from then on, which is one of the two
  # reasons the whole profile list is ignored after creation.
  default_agent_pool_count = var.default_node_pool.auto_scaling.enabled ? var.default_node_pool.auto_scaling.min_count : var.default_node_pool.node_count

  # A system pool is Linux-only and always mode System, so neither is an input.
  #
  # The autoscaler bounds are written as nulls rather than merged in as an
  # object. A conditional between `{}` and a populated object unifies the two
  # sides to a single map type, which collapses mixed element types — a body
  # built that way can reach ARM with a number quoted. `ignore_null_property`
  # drops the nulls instead.
  default_agent_pool_profile = {
    name                   = var.default_node_pool.name
    mode                   = "System"
    type                   = "VirtualMachineScaleSets"
    osType                 = "Linux"
    osSKU                  = var.default_node_pool.os_sku
    vmSize                 = var.default_node_pool.vm_size
    osDiskSizeGB           = var.default_node_pool.os_disk_size_gb
    osDiskType             = var.default_node_pool.os_disk_type
    kubeletDiskType        = var.default_node_pool.kubelet_disk_type
    maxPods                = var.default_node_pool.max_pods
    enableEncryptionAtHost = var.default_node_pool.host_encryption_enabled
    enableFIPS             = var.default_node_pool.fips_enabled
    enableNodePublicIP     = var.default_node_pool.node_public_ip_enabled
    enableAutoScaling      = var.default_node_pool.auto_scaling.enabled
    count                  = local.default_agent_pool_count
    minCount               = var.default_node_pool.auto_scaling.enabled ? var.default_node_pool.auto_scaling.min_count : null
    maxCount               = var.default_node_pool.auto_scaling.enabled ? var.default_node_pool.auto_scaling.max_count : null
    availabilityZones      = var.default_node_pool.zones
    scaleDownMode          = var.default_node_pool.scale_down_mode
    vnetSubnetID           = var.default_node_pool.vnet_subnet_resource_id
    podSubnetID            = var.default_node_pool.pod_subnet_resource_id
    nodeLabels             = var.default_node_pool.node_labels
    nodeTaints             = var.default_node_pool.node_taints
    upgradeSettings = {
      maxSurge                  = var.default_node_pool.upgrade_settings.max_surge
      drainTimeoutInMinutes     = var.default_node_pool.upgrade_settings.drain_timeout_in_minutes
      nodeSoakDurationInMinutes = var.default_node_pool.upgrade_settings.node_soak_duration_in_minutes
    }
    # On an agent pool, tags is a PROPERTY. It is not the body-level `tags` the
    # rest of ARM uses, and AzAPI's schema rejects it there.
    tags = var.default_node_pool.tags
  }
}

locals {
  # Add-on configuration values are ARM strings, including the booleans — a real
  # `true` is rejected by the schema.
  key_vault_secrets_provider_config = var.key_vault_secrets_provider.enabled ? {
    enableSecretRotation = tostring(var.key_vault_secrets_provider.secret_rotation_enabled)
    rotationPollInterval = var.key_vault_secrets_provider.secret_rotation_interval
  } : null

  # ARM spells the flag the opposite way round from every SDK and from this
  # module's input, so the polarity is inverted here rather than at the call site.
  # Null stays null: unset is not the same as "NAT enabled", and sending false
  # where the caller said nothing is how an overlay cluster gets a 400.
  windows_disable_outbound_nat = try(var.windows_profile.outbound_nat_enabled, null) == null ? null : !var.windows_profile.outbound_nat_enabled

  cluster_body = {
    sku = {
      name = var.sku.name
      tier = var.sku.tier
    }
    properties = {
      kubernetesVersion = var.kubernetes_version
      dnsPrefix         = coalesce(var.dns_prefix, var.name)
      nodeResourceGroup = var.node_resource_group
      supportPlan       = var.support_plan
      enableRBAC        = var.rbac_enabled

      agentPoolProfiles = [local.default_agent_pool_profile]

      networkProfile = {
        networkPlugin     = var.network_profile.network_plugin
        networkPluginMode = var.network_profile.network_plugin_mode
        networkPolicy     = var.network_profile.network_policy
        networkDataplane  = var.network_profile.network_dataplane
        outboundType      = var.network_profile.outbound_type
        loadBalancerSku   = var.network_profile.load_balancer_sku
        podCidr           = var.network_profile.pod_cidr
        serviceCidr       = var.network_profile.service_cidr
        dnsServiceIP      = var.network_profile.dns_service_ip
      }

      apiServerAccessProfile = {
        enablePrivateCluster           = var.api_server_access_profile.private_cluster_enabled
        enablePrivateClusterPublicFQDN = var.api_server_access_profile.private_cluster_public_fqdn_enabled
        # ARM rejects the property outright on a public cluster rather than
        # ignoring it, so it is sent only where it means something.
        privateDNSZone     = var.api_server_access_profile.private_cluster_enabled ? var.api_server_access_profile.private_dns_zone : null
        authorizedIPRanges = var.api_server_access_profile.private_cluster_enabled ? null : tolist(var.api_server_access_profile.authorized_ip_ranges)
        disableRunCommand  = !var.api_server_access_profile.run_command_enabled
      }

      # Sits beside apiServerAccessProfile rather than inside it, which is where
      # ARM puts it, and gates only the public path — see the variable.
      publicNetworkAccess = var.public_network_access

      aadProfile = var.aad_profile == null ? null : {
        managed             = true
        enableAzureRBAC     = var.aad_profile.azure_rbac_enabled
        adminGroupObjectIDs = tolist(var.aad_profile.admin_group_object_ids)
        tenantID            = var.aad_profile.tenant_id
      }

      autoUpgradeProfile = {
        upgradeChannel       = var.auto_upgrade_profile.upgrade_channel
        nodeOSUpgradeChannel = var.auto_upgrade_profile.node_os_upgrade_channel
      }

      upgradeSettings = var.upgrade_override == null ? null : {
        overrideSettings = {
          forceUpgrade = var.upgrade_override.force_upgrade
          until        = var.upgrade_override.until
        }
      }

      nodeProvisioningProfile = {
        mode = var.node_provisioning_profile.mode
      }

      disableLocalAccounts = var.local_accounts_disabled
      diskEncryptionSetID  = var.disk_encryption_set_resource_id

      oidcIssuerProfile = {
        enabled = var.oidc_issuer_enabled
      }

      securityProfile = {
        workloadIdentity = {
          enabled = var.workload_identity_enabled
        }
        imageCleaner = {
          enabled       = var.image_cleaner.enabled
          intervalHours = var.image_cleaner.interval_hours
        }
        defender = var.microsoft_defender == null ? null : {
          logAnalyticsWorkspaceResourceId = var.microsoft_defender.log_analytics_workspace_resource_id
          securityMonitoring = {
            enabled = true
          }
        }
        azureKeyVaultKms = var.key_management_service == null ? null : {
          enabled               = true
          keyId                 = var.key_management_service.key_vault_key_id
          keyVaultNetworkAccess = var.key_management_service.key_vault_network_access
          keyVaultResourceId    = var.key_management_service.key_vault_resource_id
        }
        # Sent as an explicit Enabled or Disabled rather than omitted when off.
        # `ignore_null_property` drops a null, so emitting one for `false` would
        # make turning the flag back off a no-op that never shows as drift —
        # a clean plan against a cluster that is still encrypting.
        kubernetesResourceObjectEncryptionProfile = var.key_management_service == null ? null : {
          infrastructureEncryption = var.key_management_service.infrastructure_encryption ? "Enabled" : "Disabled"
        }
      }

      addonProfiles = {
        azurepolicy = {
          enabled = var.azure_policy_enabled
        }
        azureKeyvaultSecretsProvider = {
          enabled = var.key_vault_secrets_provider.enabled
          config  = local.key_vault_secrets_provider_config
        }
      }

      ingressProfile = {
        applicationLoadBalancer = {
          enabled = var.ingress_profile.application_load_balancer_enabled
        }
        gatewayAPI = var.ingress_profile.gateway_api_installation == null ? null : {
          installation = var.ingress_profile.gateway_api_installation
        }
      }

      workloadAutoScalerProfile = {
        keda = {
          enabled = var.workload_autoscaler_profile.keda_enabled
        }
        verticalPodAutoscaler = {
          enabled = var.workload_autoscaler_profile.vertical_pod_autoscaler_enabled
        }
      }

      metricsProfile = {
        costAnalysis = {
          enabled = var.cost_analysis_enabled
        }
      }

      identityProfile = var.kubelet_identity == null ? null : {
        kubeletidentity = {
          clientId   = var.kubelet_identity.client_id
          objectId   = var.kubelet_identity.object_id
          resourceId = var.kubelet_identity.user_assigned_resource_id
        }
      }

      linuxProfile = var.linux_profile == null ? null : {
        adminUsername = var.linux_profile.admin_username
        ssh = {
          publicKeys = [{
            keyData = var.linux_profile.ssh_public_key
          }]
        }
      }

      windowsProfile = var.windows_profile == null ? null : {
        adminUsername      = var.windows_profile.admin_username
        licenseType        = var.windows_profile.license_type
        enableCSIProxy     = var.windows_profile.csi_proxy_enabled
        disableOutboundNat = local.windows_disable_outbound_nat
        gmsaProfile = var.windows_profile.gmsa_enabled ? {
          enabled        = true
          dnsServer      = var.windows_profile.gmsa_dns_server
          rootDomainName = var.windows_profile.gmsa_root_domain_name
        } : null
      }
    }
  }

  # The password is the only secret in the body. Keeping it in `sensitive_body`
  # holds it out of plan output; it is still in state, which is why the variable
  # asks for an ephemeral source.
  sensitive_cluster_body = var.windows_profile == null ? null : {
    properties = {
      windowsProfile = {
        adminPassword = var.windows_profile.admin_password
      }
    }
  }
}

locals {
  # Every role this module assigns, as the caller spelled it — a display name or
  # an ARM resource ID. Deduplication happens in `role_definition_resource_ids`.
  role_definition_names = [for v in values(var.role_assignments) : v.role_definition_id_or_name]

  role_definition_name_to_resource_id = length(local.role_definition_names) > 0 ? {
    for definition in data.azapi_resource_list.role_definitions[0].output.results : definition.role_name => definition.id
  } : {}

  # Keyed by role, not by assignment key: a role definition is a property of the
  # ROLE, so two assignments naming the same role share one entry. An entry that is
  # already a resource ID falls through the lookup untouched and maps to itself.
  role_definition_resource_ids = {
    for name in toset(local.role_definition_names) :
    name => lookup(local.role_definition_name_to_resource_id, name, name)
  }
}

# -----------------------------------------------------------------------------
# Cluster
# -----------------------------------------------------------------------------

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = local.api_version
  body      = local.cluster_body
  # The body is mostly optional nested objects, and a null inside one is "leave
  # this alone", not "reset it". Sending them would flatten server-assigned
  # defaults on every apply.
  ignore_null_property   = true
  sensitive_body         = local.sensitive_cluster_body
  sensitive_body_version = var.windows_profile == null ? null : { "properties.windowsProfile.adminPassword" = var.windows_profile_password_version }
  response_export_values = {
    current_kubernetes_version          = "properties.currentKubernetesVersion"
    fqdn                                = "properties.fqdn"
    private_fqdn                        = "properties.privateFQDN"
    node_resource_group                 = "properties.nodeResourceGroup"
    oidc_issuer_url                     = "properties.oidcIssuerProfile.issuerURL"
    kubelet_identity                    = "properties.identityProfile.kubeletidentity"
    key_vault_secrets_provider_identity = "properties.addonProfiles.azureKeyvaultSecretsProvider.identity"
    application_load_balancer_identity  = "properties.ingressProfile.applicationLoadBalancer.identity"
  }
  tags = var.tags

  identity {
    type         = local.identity_type
    identity_ids = var.managed_identities.system_assigned ? null : tolist(var.managed_identities.user_assigned_resource_ids)
  }

  timeouts {
    create = var.timeouts.create
    read   = var.timeouts.read
    update = var.timeouts.update
    delete = var.timeouts.delete
  }

  lifecycle {
    ignore_changes = [
      body.properties.agentPoolProfiles,
      body.properties.kubernetesVersion,
    ]
  }
}

# `kubernetesVersion` is ignored on the cluster above, so the input is applied
# here instead. `locks` serialises it against anything else writing to the same
# cluster — an upgrade is a long call, and a concurrent PUT during one fails.
resource "azapi_update_resource" "kubernetes_version" {
  count = var.kubernetes_version == null ? 0 : 1

  type        = local.api_version
  resource_id = azapi_resource.this.id
  body = {
    properties = {
      kubernetesVersion = var.kubernetes_version
    }
  }
  locks = [azapi_resource.this.id]

  # An upgrade is the longest call this module makes — every pool rolls, one
  # node at a time within max_surge — so it takes the cluster's own budget
  # rather than AzAPI's default.
  timeouts {
    create = var.timeouts.update
    read   = var.timeouts.read
    update = var.timeouts.update
    delete = var.timeouts.delete
  }
}

# -----------------------------------------------------------------------------
# Lock
# -----------------------------------------------------------------------------

resource "azapi_resource" "lock" {
  count = var.lock != null ? 1 : 0

  name      = coalesce(var.lock.name, "lock-${var.name}")
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Authorization/locks@2020-05-01"
  body = {
    properties = {
      level = var.lock.kind
      notes = var.lock.kind == "CanNotDelete" ? "Cannot be deleted." : "Cannot be modified."
    }
  }
}

# -----------------------------------------------------------------------------
# Role assignments
# -----------------------------------------------------------------------------
# AzAPI has no equivalent of azurerm's `role_definition_name`, so role names are
# resolved against a subscription-scope listing, as the AVM interfaces module
# does.
#
# Assignment names are random UUIDs. ARM makes the name the resource identity,
# so deriving it from the principal would let an unknown-at-plan-time principal
# ID force a replacement. `name` is exposed for callers adopting an existing
# assignment.

data "azapi_resource_list" "role_definitions" {
  count = length(local.role_definition_names) > 0 ? 1 : 0

  parent_id = local.provider_subscription_resource_id
  type      = "Microsoft.Authorization/roleDefinitions@2022-04-01"
  response_export_values = {
    results = "value[].{id: id, role_name: properties.roleName}"
  }
}

resource "random_uuid" "role_assignment_name" {
  for_each = var.role_assignments
}

resource "azapi_resource" "role_assignments" {
  for_each = var.role_assignments

  name      = coalesce(each.value.name, random_uuid.role_assignment_name[each.key].result)
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  body = {
    properties = {
      condition                          = each.value.condition
      conditionVersion                   = each.value.condition_version
      delegatedManagedIdentityResourceId = each.value.delegated_managed_identity_resource_id
      description                        = each.value.description
      principalId                        = each.value.principal_id
      principalType                      = each.value.principal_type
      roleDefinitionId                   = local.role_definition_resource_ids[each.value.role_definition_id_or_name]
    }
  }

  lifecycle {
    precondition {
      # An unresolved name falls through the `lookup` default in
      # `role_definition_resource_ids` and reaches ARM as a bare string in
      # `roleDefinitionId`, which fails with an error naming neither the role nor
      # this assignment. Every resolved value is an ARM ID, so it starts with "/".
      condition     = startswith(local.role_definition_resource_ids[each.value.role_definition_id_or_name], "/")
      error_message = <<-EOT
        role_assignments["${each.key}"] names the role "${each.value.role_definition_id_or_name}",
        which matched no role definition.

        Pass a role's display name exactly as Azure spells it, or a full
        role-definition resource ID. Names resolve against the roleDefinitions
        catalogue of the provider's subscription, so a CUSTOM role defined in a
        different subscription is not listed there and must be passed as an ID.
      EOT
    }
  }
}

# -----------------------------------------------------------------------------
# Diagnostic settings
# -----------------------------------------------------------------------------
# `Microsoft.Insights/diagnosticSettings` has never shipped a stable API version;
# 2021-05-01-preview is the newest and what AVM uses.

resource "azapi_resource" "diagnostic_settings" {
  for_each = var.diagnostic_settings

  name      = coalesce(each.value.name, each.key)
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
  body = {
    properties = {
      eventHubAuthorizationRuleId = each.value.event_hub_authorization_rule_resource_id
      eventHubName                = each.value.event_hub_name
      logAnalyticsDestinationType = each.value.workspace_resource_id == null ? null : each.value.log_analytics_destination_type
      logs = concat(
        [for category, enabled in each.value.log_categories : {
          category        = category
          categoryGroup   = null
          enabled         = enabled
          retentionPolicy = local.diagnostic_retention_policy
        }],
        [for group, enabled in each.value.log_groups : {
          category        = null
          categoryGroup   = group
          enabled         = enabled
          retentionPolicy = local.diagnostic_retention_policy
        }],
      )
      marketplacePartnerId = each.value.marketplace_partner_resource_id
      metrics = [for category, enabled in each.value.metric_categories : {
        category        = category
        enabled         = enabled
        retentionPolicy = local.diagnostic_retention_policy
      }]
      storageAccountId = each.value.storage_account_resource_id
      workspaceId      = each.value.workspace_resource_id
    }
  }
}
