resource "azurerm_route_table" "remote" {
  count = local.enabled ? 1 : 0

  name                = "${local.prefix}-tailnet"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}

resource "azurerm_route" "remote" {
  for_each = local.enabled ? local.remote_cidrs : {}

  name                   = "to-${each.key}"
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.remote[0].name
  address_prefix         = each.value
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.next_hop
}

resource "azurerm_subnet_route_table_association" "remote" {
  for_each = local.enabled ? toset(["management", "workload"]) : toset([])

  subnet_id      = var.subnets[each.key]
  route_table_id = azurerm_route_table.remote[0].id
}
