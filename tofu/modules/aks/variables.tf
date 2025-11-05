variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "dns_prefix" {
  description = "DNS prefix for the AKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "sku_tier" {
  description = "SKU tier for AKS (Free or Standard)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Free", "Standard"], var.sku_tier)
    error_message = "SKU tier must be Free or Standard"
  }
}

variable "automatic_upgrade_channel" {
  description = "Automatic upgrade channel"
  type        = string
  default     = "stable"

  validation {
    condition     = contains(["patch", "rapid", "stable", "node-image", "none"], var.automatic_upgrade_channel)
    error_message = "Invalid upgrade channel"
  }
}

variable "vnet_subnet_id" {
  description = "Subnet ID for AKS nodes"
  type        = string
}

variable "availability_zones" {
  description = "Availability zones for node pools"
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "service_cidr" {
  description = "Service CIDR for Kubernetes services"
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "DNS service IP"
  type        = string
  default     = "172.16.0.10"
}

variable "managed_identity_id" {
  description = "Managed identity resource ID for AKS control plane"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, demo, prod)"
  type        = string
}

# System node pool
variable "system_node_pool_vm_size" {
  description = "VM size for system node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "system_node_pool_min_count" {
  description = "Minimum node count for system pool"
  type        = number
  default     = 2
}

variable "system_node_pool_max_count" {
  description = "Maximum node count for system pool"
  type        = number
  default     = 5
}

variable "system_node_pool_node_count" {
  description = "Initial node count for system pool"
  type        = number
  default     = 2
}

variable "system_node_pool_max_pods" {
  description = "Maximum pods per node in system pool"
  type        = number
  default     = 50
}

# Capsule node pool
variable "capsule_node_pool_vm_size" {
  description = "VM size for Capsule tenant node pool"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "capsule_node_pool_min_count" {
  description = "Minimum node count for Capsule pool"
  type        = number
  default     = 2
}

variable "capsule_node_pool_max_count" {
  description = "Maximum node count for Capsule pool"
  type        = number
  default     = 10
}

variable "capsule_node_pool_node_count" {
  description = "Initial node count for Capsule pool"
  type        = number
  default     = 3
}

variable "capsule_node_pool_max_pods" {
  description = "Maximum pods per node in Capsule pool"
  type        = number
  default     = 50
}

# vCluster node pool
variable "vcluster_node_pool_vm_size" {
  description = "VM size for vCluster control plane node pool"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "vcluster_node_pool_min_count" {
  description = "Minimum node count for vCluster pool"
  type        = number
  default     = 2
}

variable "vcluster_node_pool_max_count" {
  description = "Maximum node count for vCluster pool"
  type        = number
  default     = 8
}

variable "vcluster_node_pool_node_count" {
  description = "Initial node count for vCluster pool"
  type        = number
  default     = 2
}

variable "vcluster_node_pool_max_pods" {
  description = "Maximum pods per node in vCluster pool"
  type        = number
  default     = 50
}

# Monitoring
variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for monitoring"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
