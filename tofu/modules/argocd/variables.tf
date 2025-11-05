variable "namespace" {
  description = "Namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "3.35.4"
}

variable "domain" {
  description = "Domain for ArgoCD server"
  type        = string
  default     = "argocd.local"
}
