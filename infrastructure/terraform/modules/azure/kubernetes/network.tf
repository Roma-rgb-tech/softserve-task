resource "azurerm_subnet" "nodes" {
  count = local.count

  name                 = "${local.prefix}-aks-nodes"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.virtual_network_name
  address_prefixes     = [local.node_cidr]
}
