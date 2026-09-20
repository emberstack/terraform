# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = <<-EOT
    Name of the agent pool.

    Windows pools are capped at 6 characters, not 12: the name seeds the node's
    NetBIOS hostname, and that limit is AKS's, not this module's.
  EOT
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{0,11}$", var.name))
    error_message = "name must be 1-12 characters, start with a lowercase letter, and contain only lowercase letters and digits."
  }
}

variable "cluster_resource_id" {
  type        = string
  description = "Resource ID of the managed cluster this pool belongs to."
  nullable    = false

  validation {
    condition     = can(regex("/providers/Microsoft.ContainerService/managedClusters/", var.cluster_resource_id))
    error_message = "cluster_resource_id must be a Microsoft.ContainerService/managedClusters resource ID."
  }
}

variable "vm_size" {
  type        = string
  description = "VM size for the pool's nodes. Immutable on an existing pool, so a change replaces it — see the note in `main.tf`."
  nullable    = false
}

# -----------------------------------------------------------------------------
# Node configuration
# -----------------------------------------------------------------------------

variable "mode" {
  type        = string
  default     = "User"
  description = "`System` pools host the cluster's own control components and a cluster must always keep at least one; `User` pools host workloads."
  nullable    = false

  validation {
    condition     = contains(["System", "User", "Gateway"], var.mode)
    error_message = "mode must be one of: System, User, Gateway."
  }
}

variable "os_type" {
  type        = string
  default     = "Linux"
  description = "Node operating system. Drives the API behaviour, so a Windows pool needs this set — `os_sku` alone is not enough."
  nullable    = false

  validation {
    condition     = contains(["Linux", "Windows"], var.os_type)
    error_message = "os_type must be one of: Linux, Windows."
  }

  validation {
    condition     = var.os_type != "Windows" || length(var.name) <= 6
    error_message = "A Windows pool's name must be 1-6 characters — the name seeds the node's NetBIOS hostname."
  }
}

variable "os_sku" {
  type        = string
  default     = null
  description = <<-EOT
    Node image SKU — `Ubuntu`, `AzureLinux`, `Windows2019`, `Windows2022`,
    `Windows2025`, `WindowsAnnual`, and whatever else AKS has added since.

    Deliberately not validated against a fixed list. ARM adds SKUs faster than a
    hardcoded `contains()` can be updated, and a stale list rejects a
    configuration Azure would have accepted. ARM rejects an unknown value itself.

    `Windows2025` and later reject `fips_enabled = false` outright.
  EOT
}

variable "os_disk_size_gb" {
  type        = number
  default     = null
  description = "OS disk size. Null takes the image's default."
}

variable "os_disk_type" {
  type        = string
  default     = "Ephemeral"
  description = "`Ephemeral` puts the OS disk on the node's local NVMe — faster and not separately billed, but only available on a VM size that has a cache or temp disk. Use `Managed` on the ones that do not."
  nullable    = false

  validation {
    condition     = contains(["Ephemeral", "Managed"], var.os_disk_type)
    error_message = "os_disk_type must be one of: Ephemeral, Managed."
  }
}

variable "kubelet_disk_type" {
  type        = string
  default     = null
  description = "Where kubelet keeps its ephemeral state — `OS` or `Temporary`. Null takes the Azure default."

  validation {
    condition     = var.kubelet_disk_type == null || contains(["OS", "Temporary"], coalesce(var.kubelet_disk_type, "OS"))
    error_message = "kubelet_disk_type must be one of: OS, Temporary."
  }
}

variable "max_pods" {
  type        = number
  default     = null
  description = "Maximum pods per node. Null takes the network plugin's default. Create-only."
}

variable "host_encryption_enabled" {
  type        = bool
  default     = true
  description = "Encrypt the node's temp disk and OS/data disk caches at the host. Create-only, and requires the feature to be registered on the subscription."
  nullable    = false
}

variable "fips_enabled" {
  type        = bool
  default     = false
  description = "Use the FIPS-validated node image. Create-only, and mandatory on `Windows2025` and later — ARM returns `WindowsVersionCannotDisableFIPS` when it is false there."
  nullable    = false
}

variable "node_public_ip_enabled" {
  type        = bool
  default     = false
  description = "Give each node a public IP. Create-only."
  nullable    = false
}

variable "zones" {
  type        = list(string)
  default     = ["1", "2", "3"]
  description = "Availability zones for the pool's nodes. Create-only. An empty list is a regional (non-zonal) pool."
  nullable    = false
}

variable "vnet_subnet_resource_id" {
  type        = string
  default     = null
  description = "Subnet the nodes join. Null puts them in the cluster's own subnet. Create-only."
}

variable "pod_subnet_resource_id" {
  type        = string
  default     = null
  description = "Subnet the pods draw addresses from, for a dynamic-allocation cluster. Create-only."
}

variable "node_labels" {
  type        = map(string)
  default     = {}
  description = "Kubernetes labels applied to every node in the pool."
  nullable    = false
}

variable "node_taints" {
  type        = list(string)
  default     = []
  description = "Kubernetes taints applied to every node in the pool, as `key=value:Effect`. Create-only on AKS."
  nullable    = false
}

variable "orchestrator_version" {
  type        = string
  default     = null
  description = "Pin the pool to a Kubernetes version. Null follows the cluster, which is what you want unless you are staging an upgrade pool by pool."
}

# -----------------------------------------------------------------------------
# Scaling
# -----------------------------------------------------------------------------

variable "auto_scaling" {
  type = object({
    enabled   = optional(bool, true)
    min_count = optional(number, 1)
    max_count = optional(number, 3)
  })
  default     = {}
  description = "Cluster autoscaler settings for this pool. With `enabled`, the pool's size is the autoscaler's to decide and Terraform stops reconciling it."
  nullable    = false

  validation {
    condition     = !var.auto_scaling.enabled || var.auto_scaling.min_count <= var.auto_scaling.max_count
    error_message = "auto_scaling.min_count must not exceed max_count."
  }
}

variable "node_count" {
  type        = number
  default     = 1
  description = <<-EOT
    Node count, used only when `auto_scaling.enabled` is false — and reconciled,
    so changing it on an existing fixed-size pool scales it.

    With the autoscaler on, the property is not sent at all and the pool's size
    is entirely the autoscaler's. See the note on `count` in `main.tf`.
  EOT
  nullable    = false
}

variable "scale_down_mode" {
  type        = string
  default     = null
  description = "`Delete` removes nodes on scale-down; `Deallocate` stops them and keeps the disks. Null takes the Azure default."

  validation {
    condition     = var.scale_down_mode == null || contains(["Delete", "Deallocate"], coalesce(var.scale_down_mode, "Delete"))
    error_message = "scale_down_mode must be one of: Delete, Deallocate."
  }
}

variable "upgrade_settings" {
  type = object({
    max_surge                     = optional(string, "10%")
    drain_timeout_in_minutes      = optional(number, null)
    node_soak_duration_in_minutes = optional(number, null)
  })
  default     = {}
  description = "How aggressively the pool rolls during an upgrade. `max_surge` is a node count or a percentage of the pool."
  nullable    = false
}

variable "spot" {
  type = object({
    eviction_policy = optional(string, "Delete")
    max_price       = optional(number, -1)
  })
  default     = null
  description = <<-EOT
    Run the pool on spot capacity. Null is a regular pool.

    `max_price` of -1 pays up to the on-demand price and is evicted only on
    capacity pressure. A spot pool is tainted `kubernetes.azure.com/scalesetpriority=spot:NoSchedule`
    by AKS, so nothing lands on it without a matching toleration. Create-only:
    an existing regular pool cannot be converted.
  EOT

  validation {
    condition     = var.spot == null || contains(["Delete", "Deallocate"], try(var.spot.eviction_policy, ""))
    error_message = "spot.eviction_policy must be one of: Delete, Deallocate."
  }
}

# -----------------------------------------------------------------------------
# Windows
# -----------------------------------------------------------------------------

variable "windows_outbound_nat_enabled" {
  type        = bool
  default     = null
  description = <<-EOT
    Windows pools only. Null leaves the property unset and lets Azure decide.

    Setting this to `false` on an overlay cluster is rejected with
    `DisableWindowsOutboundNatNotSupported` — an overlay pod CIDR is not
    VNet-routable, so the node has to SNAT pod traffic to its own host IP, which
    is exactly what OutboundNAT does. The cost of leaving it on is the default 64
    SNAT ports per host IP.

    Azure records the value per pool and is not consistent about it: some pools
    carry an explicit `false`, others carry nothing at all. It is create-only, so
    setting it to something the pool does not already have replaces the pool.
  EOT
}

# -----------------------------------------------------------------------------
# Interfaces
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the pool's nodes and to the scale set behind it."
  nullable    = false
}

variable "create_before_destroy" {
  type        = bool
  default     = false
  description = <<-EOT
    Build the replacement pool before tearing the old one down, so a replacing
    change — a `vm_size` change, in practice — does not take the pool's capacity
    to zero first.

    The cost is the pool's ARM name. Two pools on one cluster cannot share a
    name, so the replacement is created as `<name>` plus a four-character
    suffix, and that generated name is then held fixed for the pool's life. Two
    consequences: the name in `kubectl get nodes` is not `name`, and the four
    characters come out of the pool's name budget. On a Windows pool, whose
    ceiling is six characters, there is no room at all — so it is rejected there
    rather than failing at apply.

    Changing `name` itself still replaces the pool. A `terraform_data` keeper
    carries the logical name, because the generated one has to be ignored.

    **Set this when the pool is created.** Flipping it on an existing pool moves
    it between two Terraform addresses with nothing ordering them, so that apply
    can destroy the old pool before building the new one — the exact gap the
    option exists to avoid. Turning it on later means draining the pool
    deliberately, or accepting one last outage to buy out of the next.
  EOT
  nullable    = false

  validation {
    condition     = !var.create_before_destroy || var.os_type != "Windows"
    error_message = "create_before_destroy cannot be used on a Windows pool — the generated four-character suffix does not fit inside the 6-character Windows name limit."
  }

  validation {
    condition     = !var.create_before_destroy || length(var.name) <= 8
    error_message = "create_before_destroy appends a four-character suffix, so name must be 8 characters or fewer to stay within the 12-character pool name limit."
  }
}

variable "timeouts" {
  type = object({
    create = optional(string, "60m")
    read   = optional(string, null)
    update = optional(string, "60m")
    delete = optional(string, "60m")
  })
  default     = {}
  description = <<-EOT
    How long each operation on the pool is allowed to take.

    The defaults are 60 minutes, matching what the AzureRM provider budgets for
    a node pool, rather than AzAPI's generic 30 — a pool rolls a node at a time
    within `upgrade_settings.max_surge`, so the time it needs scales with the
    node count. `read` left null takes AzAPI's default.
  EOT
  nullable    = false
}
