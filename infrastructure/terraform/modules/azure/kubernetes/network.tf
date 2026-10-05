# A subnet of the nodes' own, without the VMs' network security group: AKS
# opens what its load balancers need in a group it manages itself, on the
# node interfaces, and a subnet-level group it does not know about would
# silently drop the visitors.
resource "azurerm_subnet" "nodes" {
  count = local.count

  name                 = "${local.prefix}-aks-nodes"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.virtual_network_name
  address_prefixes     = [local.node_cidr]
}
