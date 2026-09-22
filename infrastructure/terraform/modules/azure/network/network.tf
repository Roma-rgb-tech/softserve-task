resource "azurerm_resource_group" "main" {
  count = local.count

  name     = "${local.prefix}-rg"
  location = local.location
  tags     = local.tags

  lifecycle {
    precondition {
      condition     = local.location != null
      error_message = "The catalog has no azure region for default_region ${local.token}. Add it under catalog.region.azure."
    }
  }
}

resource "azurerm_virtual_network" "main" {
  count = local.count

  name                = "${local.prefix}-vnet"
  location            = azurerm_resource_group.main[0].location
  resource_group_name = azurerm_resource_group.main[0].name
  address_space       = [var.config.network.vpc_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "management" {
  count = local.count

  name                 = "${local.prefix}-management"
  resource_group_name  = azurerm_resource_group.main[0].name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.config.network.management_subnet_cidr]
}

resource "azurerm_subnet" "workload" {
  count = local.count

  name                 = "${local.prefix}-workload"
  resource_group_name  = azurerm_resource_group.main[0].name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.config.network.workload_subnet_cidr]

  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "database" {
  count = local.database_count

  name                            = "${local.prefix}-database"
  resource_group_name             = azurerm_resource_group.main[0].name
  virtual_network_name            = azurerm_virtual_network.main[0].name
  address_prefixes                = [local.database_cidrs[0]]
  default_outbound_access_enabled = false

  lifecycle {
    ignore_changes = [service_endpoints]
  }

  delegation {
    name = "postgresql-flexible-server"

    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}
