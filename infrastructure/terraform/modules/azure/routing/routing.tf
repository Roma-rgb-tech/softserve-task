resource "azurerm_public_ip" "nat" {
  count = local.count

  name                = "${local.prefix}-nat-ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "main" {
  count = local.count

  name                = "${local.prefix}-nat"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  count = local.count

  nat_gateway_id       = azurerm_nat_gateway.main[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "workload" {
  count = local.count

  subnet_id      = var.subnets.workload
  nat_gateway_id = azurerm_nat_gateway.main[0].id
}
