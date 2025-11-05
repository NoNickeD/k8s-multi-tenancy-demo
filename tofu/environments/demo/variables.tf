variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "westeurope"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "demo"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.30"
}

variable "owner_email" {
  description = "Email of the resource owner (for tagging)"
  type        = string
}

variable "aks_admin_user_emails" {
  description = "List of Azure AD user emails that should have admin access to the AKS cluster"
  type        = list(string)
  default     = []
}
