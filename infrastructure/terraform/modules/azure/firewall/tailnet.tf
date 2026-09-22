resource "azurerm_network_security_rule" "tailnet_forward" {
  count = local.has_bastion && local.tailnet && length(local.remote_cidrs) > 0 ? 1 : 0

  name                         = "tailnet-forward"
  resource_group_name          = var.resource_group_name
  network_security_group_name  = azurerm_network_security_group.vms[0].name
  priority                     = 3900
  direction                    = "Inbound"
  access                       = "Allow"
  protocol                     = "*"
  source_port_range            = "*"
  destination_port_range       = "*"
  source_address_prefixes      = [var.config.network.management_subnet_cidr, var.config.network.workload_subnet_cidr]
  destination_address_prefixes = local.remote_cidrs
}

resource "azurerm_network_security_rule" "tailnet_direct" {
  count = local.has_bastion && local.tailnet ? 1 : 0

  name                                       = "tailnet-direct"
  resource_group_name                        = var.resource_group_name
  network_security_group_name                = azurerm_network_security_group.vms[0].name
  priority                                   = 3910
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Udp"
  source_port_range                          = "*"
  destination_port_range                     = "41641"
  source_address_prefix                      = "Internet"
  destination_application_security_group_ids = [local.group_ids["bastion"]]

  lifecycle {
    replace_triggered_by = [azurerm_application_security_group.this]
  }
}
