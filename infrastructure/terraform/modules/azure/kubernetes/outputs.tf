output "cluster" {
  description = "The managed cluster, for Ansible to fetch credentials for. Null when AKS is not in use."
  value = local.enabled ? {
    cloud    = local.cloud
    kind     = "aks"
    name     = azurerm_kubernetes_cluster.main[0].name
    location = var.location
    group    = var.resource_group_name
    project  = null
    endpoint = azurerm_kubernetes_cluster.main[0].fqdn
    version  = azurerm_kubernetes_cluster.main[0].current_kubernetes_version
    context  = local.name
  } : null
}

output "external_secrets_reader" {
  description = "The identity External Secrets reads the cluster's Key Vault secrets as. enabled is known at plan time; principal_id only after apply."
  value = {
    enabled      = local.external_secrets
    principal_id = local.external_secrets ? azurerm_user_assigned_identity.external_secrets[0].principal_id : null
    client_id    = local.external_secrets ? azurerm_user_assigned_identity.external_secrets[0].client_id : null
  }
}
