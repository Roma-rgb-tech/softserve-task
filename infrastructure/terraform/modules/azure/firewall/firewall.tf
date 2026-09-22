resource "azurerm_application_security_group" "this" {
  for_each = local.enabled ? local.groups : tomap({})

  name                = "${local.prefix}-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = merge(local.tags, { description = each.value })
}

resource "azurerm_network_security_group" "vms" {
  count = local.enabled ? 1 : 0

  name                = "${local.prefix}-vms"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_network_security_rule" "ingress" {
  for_each = local.prioritized

  name                        = each.value.name
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vms[0].name
  priority                    = each.value.priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(each.value.port)

  source_address_prefix                      = each.value.cidr
  source_application_security_group_ids      = each.value.source_group == null ? null : [local.group_ids[each.value.source_group]]
  destination_application_security_group_ids = [local.group_ids[each.value.group]]

  lifecycle {
    replace_triggered_by = [azurerm_application_security_group.this]
  }
}

resource "azurerm_network_security_rule" "deny_virtual_network" {
  count = local.enabled ? 1 : 0

  name                        = "deny-virtual-network"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vms[0].name
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
}

resource "azurerm_subnet_network_security_group_association" "vms" {
  for_each = local.enabled ? toset(["management", "workload"]) : toset([])

  subnet_id                 = var.subnets[each.key]
  network_security_group_id = azurerm_network_security_group.vms[0].id
}
