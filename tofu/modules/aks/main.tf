# AKS Module for Multi-Tenancy Demo

resource "azurerm_kubernetes_cluster" "aks" {
  name                      = var.cluster_name
  location                  = var.location
  resource_group_name       = var.resource_group_name
  node_resource_group       = "${var.resource_group_name}-nodes"
  dns_prefix                = var.dns_prefix
  kubernetes_version        = var.kubernetes_version
  sku_tier                  = var.sku_tier
  automatic_upgrade_channel = var.automatic_upgrade_channel

  # Workload identity and OIDC
  workload_identity_enabled = true
  oidc_issuer_enabled       = true

  # Default node pool (system)
  default_node_pool {
    name                = "system"
    vm_size             = var.system_node_pool_vm_size
    vnet_subnet_id      = var.vnet_subnet_id
    zones               = var.availability_zones
    auto_scaling_enabled = true
    min_count           = var.system_node_pool_min_count
    max_count           = var.system_node_pool_max_count
    node_count          = var.system_node_pool_node_count
    max_pods            = var.system_node_pool_max_pods
    os_disk_type        = "Managed"

    node_labels = {
      "nodepool-type" = "system"
      "workload-type" = "platform"
      "environment"   = var.environment
    }

    only_critical_addons_enabled = true
    temporary_name_for_rotation  = "systmp"

    upgrade_settings {
      drain_timeout_in_minutes      = 30
      max_surge                     = "33%"
      node_soak_duration_in_minutes = 0
    }
  }

  # Network configuration
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    network_data_plane  = "cilium"
    outbound_type       = "loadBalancer"
    load_balancer_sku   = "standard"
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
  }

  # Identity
  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  # RBAC with Azure AD
  role_based_access_control_enabled = true

  azure_active_directory_role_based_access_control {
    tenant_id          = var.tenant_id
    azure_rbac_enabled = true
  }

  # Workload autoscaling - KEDA and VPA enabled!
  workload_autoscaler_profile {
    keda_enabled                    = true
    vertical_pod_autoscaler_enabled = true
  }

  # Key Vault secrets provider
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  # Monitoring
  dynamic "oms_agent" {
    for_each = var.log_analytics_workspace_id != null ? [1] : []
    content {
      msi_auth_for_monitoring_enabled = true
      log_analytics_workspace_id      = var.log_analytics_workspace_id
    }
  }

  # Enhanced features
  azure_policy_enabled             = true
  image_cleaner_enabled            = true
  image_cleaner_interval_hours     = 24
  http_application_routing_enabled = false

  # Cost analysis
  cost_analysis_enabled = true

  tags = var.tags

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count,
      kubernetes_version,
      tags
    ]
  }
}

# Capsule node pool for soft multi-tenancy workloads
resource "azurerm_kubernetes_cluster_node_pool" "capsule" {
  name                  = "capsule"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.capsule_node_pool_vm_size
  vnet_subnet_id        = var.vnet_subnet_id
  zones                 = var.availability_zones

  auto_scaling_enabled = true
  min_count           = var.capsule_node_pool_min_count
  max_count           = var.capsule_node_pool_max_count
  node_count          = var.capsule_node_pool_node_count
  max_pods            = var.capsule_node_pool_max_pods
  os_disk_type        = "Managed"

  node_labels = {
    "nodepool-type" = "capsule"
    "workload-type" = "tenant"
    "tenant-mode"   = "soft-isolation"
    "environment"   = var.environment
  }

  upgrade_settings {
    drain_timeout_in_minutes      = 30
    max_surge                     = "33%"
    node_soak_duration_in_minutes = 0
  }

  tags = merge(var.tags, {
    "nodepool-type" = "capsule"
    "tenant-mode"   = "soft-isolation"
  })
}

# vCluster node pool for hard multi-tenancy control planes
resource "azurerm_kubernetes_cluster_node_pool" "vcluster" {
  name                  = "vcluster"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.vcluster_node_pool_vm_size
  vnet_subnet_id        = var.vnet_subnet_id
  zones                 = var.availability_zones

  auto_scaling_enabled = true
  min_count           = var.vcluster_node_pool_min_count
  max_count           = var.vcluster_node_pool_max_count
  node_count          = var.vcluster_node_pool_node_count
  max_pods            = var.vcluster_node_pool_max_pods
  os_disk_type        = "Managed"

  node_labels = {
    "nodepool-type" = "vcluster"
    "workload-type" = "vcluster-control-plane"
    "tenant-mode"   = "hard-isolation"
    "environment"   = var.environment
  }

  upgrade_settings {
    drain_timeout_in_minutes      = 30
    max_surge                     = "33%"
    node_soak_duration_in_minutes = 0
  }

  tags = merge(var.tags, {
    "nodepool-type" = "vcluster"
    "tenant-mode"   = "hard-isolation"
  })
}

# Monitoring data collection rule
resource "azurerm_monitor_data_collection_rule" "aks" {
  name                = "dcr-${var.location}-container"
  resource_group_name = var.resource_group_name
  location            = var.location

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      streams        = ["Microsoft-ContainerInsights-Group-Default"]
      extension_name = "ContainerInsights"
      extension_json = jsonencode({
        "dataCollectionSettings" : {
          "interval" : "1m",
          "namespaceFilteringMode" : "Off",
          "enableContainerLogV2" : true
        }
      })
    }
  }

  data_flow {
    destinations = ["ciworkspace"]
    streams      = ["Microsoft-ContainerInsights-Group-Default"]
  }

  destinations {
    log_analytics {
      name                  = "ciworkspace"
      workspace_resource_id = var.log_analytics_workspace_id
    }
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_monitor_data_collection_rule_association" "aks" {
  name                    = "ContainerInsightsExtension"
  target_resource_id      = azurerm_kubernetes_cluster.aks.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.aks.id
  description             = "Association of container insights data collection rule"
}
