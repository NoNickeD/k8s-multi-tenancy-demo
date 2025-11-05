terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    kubernetes = {
      source                = "hashicorp/kubernetes"
      version               = "~> 2.32"
      configuration_aliases = [kubernetes]
    }
    helm = {
      source                = "hashicorp/helm"
      version               = "~> 2.16"
      configuration_aliases = [helm]
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}



provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
  subscription_id = var.subscription_id
}

# Kubernetes provider configured to use the AKS cluster
# The provider will use the current context from kubeconfig
# The null_resource will set the correct context before ArgoCD deployment
provider "kubernetes" {
  config_path = "~/.kube/config"
}

# Helm provider configured to use the AKS cluster
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}
