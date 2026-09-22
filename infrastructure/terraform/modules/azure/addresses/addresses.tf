resource "azurerm_public_ip" "public" {
  for_each = local.public_vms

  name                = "${local.prefix}-${each.key}-ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = local.zone == null ? null : [local.zone]
  tags                = merge(local.tags, { role = each.value.role })
}
