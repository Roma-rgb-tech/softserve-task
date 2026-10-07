resource "azurerm_kubernetes_cluster" "main" {
  count = local.count

  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name
  node_resource_group = "${local.prefix}-aks-nodes-rg"
  dns_prefix          = local.prefix
  kubernetes_version  = local.version
  sku_tier            = "Free"

  default_node_pool {
    name                        = "system"
    vm_size                     = local.vm_size
    node_count                  = local.node_count
    vnet_subnet_id              = azurerm_subnet.nodes[0].id
    os_disk_size_gb             = local.disk_gb
    os_sku                      = "Ubuntu"
    temporary_name_for_rotation = "rotation"
    node_labels                 = { role = "kubernetes-node" }
    tags                        = local.tags

    upgrade_settings {
      max_surge = "1"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = local.pod_cidr
    service_cidr        = local.service_cidr
    dns_service_ip      = cidrhost(local.service_cidr, 10)
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  api_server_access_profile {
    authorized_ip_ranges = local.api_cidrs
  }

  role_based_access_control_enabled = true

  tags = local.tags

  lifecycle {
    precondition {
      condition     = local.vm_size != null
      error_message = "catalog.size.azure has no entry for kubernetes.node_size."
    }

    precondition {
      condition     = length(local.api_cidrs) > 0
      error_message = "Nothing would be allowed to reach the AKS API. Set kubernetes.api_allowed_cidrs, or allowed_cidrs on the bastion."
    }
  }
}

resource "azurerm_role_assignment" "network" {
  count = local.count

  scope                = var.virtual_network_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main[0].identity[0].principal_id
}
