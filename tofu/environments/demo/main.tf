# Main Configuration for K8s Autoscaling Demo

# Data sources
data "azurerm_client_config" "current" {}

# Local variables
locals {
  name_prefix = "k8s-multitenancy"
  common_tags = {
    Environment = var.environment
    Project     = "k8s-multi-tenancy-demo"
    ManagedBy   = "OpenTofu"
    Owner       = var.owner_email
  }
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}-${var.location}"
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${local.name_prefix}-${var.location}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

# Managed Identity for AKS
module "identity" {
  source = "../../modules/identity"

  identity_name       = "id-${local.name_prefix}-${var.location}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Networking
module "networking" {
  source = "../../modules/networking"

  vnet_name           = "vnet-${local.name_prefix}-${var.location}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]
  aks_subnet_name     = "snet-aks"
  aks_subnet_prefixes = ["10.0.1.0/24"]
  tags                = local.common_tags
}

# Azure Container Registry
resource "azurerm_container_registry" "main" {
  name                = replace("acr${local.name_prefix}${var.location}", "-", "")
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  admin_enabled       = false

  tags = local.common_tags
}

# Azure Key Vault
resource "azurerm_key_vault" "main" {
  name                        = "kv-${local.name_prefix}-${random_string.kv_suffix.result}"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"
  rbac_authorization_enabled  = true

  tags = local.common_tags
}

resource "random_string" "kv_suffix" {
  length  = 4
  special = false
  upper   = false
}

# AKS Cluster with KEDA and VPA enabled
module "aks" {
  source = "../../modules/aks"

  cluster_name               = "aks-${local.name_prefix}-${var.location}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  dns_prefix                 = "aks-${local.name_prefix}"
  kubernetes_version         = var.kubernetes_version
  sku_tier                   = "Standard"
  automatic_upgrade_channel  = "stable"
  vnet_subnet_id             = module.networking.aks_subnet_id
  managed_identity_id        = module.identity.id
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  environment                = var.environment
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # System node pool (for platform services: ArgoCD, Prometheus, Grafana, etc.)
  system_node_pool_vm_size    = "Standard_D2s_v3"
  system_node_pool_min_count  = 2
  system_node_pool_max_count  = 5
  system_node_pool_node_count = 2

  # Capsule node pool (for soft multi-tenancy workloads)
  capsule_node_pool_vm_size    = "Standard_D4s_v3"
  capsule_node_pool_min_count  = 2
  capsule_node_pool_max_count  = 10
  capsule_node_pool_node_count = 3

  # vCluster node pool (for hard multi-tenancy control planes)
  vcluster_node_pool_vm_size    = "Standard_D4s_v3"
  vcluster_node_pool_min_count  = 2
  vcluster_node_pool_max_count  = 8
  vcluster_node_pool_node_count = 2

  tags = local.common_tags

  depends_on = [module.networking, module.identity]
}

# Federated Identity Credential for External Secrets Operator
# This needs to be created after AKS to get the OIDC issuer URL
resource "azurerm_federated_identity_credential" "eso" {
  name                = "eso-federated-identity"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = module.identity.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:external-secrets:external-secrets-operator"

  depends_on = [module.aks]
}

# Role assignments
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity_object_id
}

resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = module.networking.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = module.aks.kubelet_identity_object_id
}

resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.aks.key_vault_secrets_provider.secret_identity_object_id
}

resource "azurerm_role_assignment" "identity_kv_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = module.identity.principal_id
}

# Azure Kubernetes Service RBAC Cluster Admin for admin users
resource "azurerm_role_assignment" "aks_rbac_cluster_admin_users" {
  count                = length(var.aks_admin_user_emails)
  scope                = module.aks.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azuread_user.aks_admin_users[count.index].object_id

  depends_on = [module.aks]
}

# Get AKS credentials using local-exec
# This runs after the cluster is created and RBAC is configured
resource "null_resource" "get_aks_credentials" {
  triggers = {
    cluster_id = module.aks.id
  }

  provisioner "local-exec" {
    command = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.aks.name} --overwrite-existing"
  }

  depends_on = [
    module.aks,
    azurerm_role_assignment.aks_rbac_cluster_admin_users
  ]
}

# ArgoCD installation
# Deployed after getting cluster credentials
module "argocd" {
  source = "../../modules/argocd"

  namespace     = "argocd"
  chart_version = "3.35.4"
  domain        = "argocd.${local.name_prefix}.local"

  depends_on = [
    module.aks,
    azurerm_role_assignment.aks_rbac_cluster_admin_users,
    null_resource.get_aks_credentials
  ]
}
