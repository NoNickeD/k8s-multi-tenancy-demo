# Data source for AKS admin users
data "azuread_user" "aks_admin_users" {
  count               = length(var.aks_admin_user_emails)
  user_principal_name = var.aks_admin_user_emails[count.index]
}
