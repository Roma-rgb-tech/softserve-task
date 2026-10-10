resource "azurerm_user_assigned_identity" "external_secrets" {
  count = local.external_secrets ? 1 : 0

  name                = "${local.prefix}-external-secrets"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "external_secrets" {
  count = local.external_secrets ? 1 : 0

  name                      = "${local.prefix}-external-secrets"
  user_assigned_identity_id = azurerm_user_assigned_identity.external_secrets[0].id
  issuer                    = azurerm_kubernetes_cluster.main[0].oidc_issuer_url
  subject                   = "system:serviceaccount:${local.external_secrets_namespace}:${local.external_secrets_account}"
  audience                  = ["api://AzureADTokenExchange"]
}
