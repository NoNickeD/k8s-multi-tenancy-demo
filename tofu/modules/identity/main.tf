# Simplified Identity Module
# Creates managed identity for AKS and federated identity credentials for workload identity

resource "azurerm_user_assigned_identity" "aks" {
  name                = var.identity_name
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Federated Identity Credential for External Secrets Operator
resource "azurerm_federated_identity_credential" "eso" {
  count               = var.oidc_issuer_url != null ? 1 : 0
  name                = "${var.identity_name}-eso"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.aks.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:external-secrets:external-secrets-operator"
}
