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
