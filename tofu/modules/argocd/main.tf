# ArgoCD Installation Module

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.32.0, < 3.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.16.0, < 3.0.0"
    }
  }
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.namespace
    labels = {
      name = var.namespace
    }
  }
}

locals {
  base_values = yamlencode({
    global = {
      domain = var.domain
    }

    server = {
      service = {
        type = "LoadBalancer"
      }

      nodeSelector = {
        "nodepool-type" = "system"
      }

      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]

      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }
    }

    controller = {
      nodeSelector = {
        "nodepool-type" = "system"
      }

      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]

      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
      }
    }

    repoServer = {
      nodeSelector = {
        "nodepool-type" = "system"
      }

      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]

      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
      }
    }

    redis = {
      nodeSelector = {
        "nodepool-type" = "system"
      }

      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]

      master = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }
    }

    dex = {
      nodeSelector = {
        "nodepool-type" = "system"
      }

      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    }

    applicationSet = {
      nodeSelector = {
        "nodepool-type" = "system"
      }

      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    }

    notifications = {
      nodeSelector = {
        "nodepool-type" = "system"
      }

      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    }
  })
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = var.chart_version

  values = [local.base_values]

  depends_on = [kubernetes_namespace.argocd]
}
