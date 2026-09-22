resource "random_id" "suffix" {
  count = local.enabled

  byte_length = 4
}

ephemeral "random_password" "administrator" {
  count = local.enabled

  length  = 40
  special = false
}

resource "azurerm_private_dns_zone" "database" {
  count = local.enabled

  name                = "${local.prefix}.private.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "database" {
  count = local.enabled

  name                  = "${local.prefix}-database"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.database[0].name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_network_security_group" "database" {
  count = local.enabled

  name                = "${local.prefix}-database"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  security_rule {
    name                       = "postgresql-from-workloads"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(local.port)
    source_address_prefixes    = var.client_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "postgresql-from-anything-else"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "database" {
  count = local.enabled

  subnet_id                 = var.subnet_id
  network_security_group_id = azurerm_network_security_group.database[0].id
}

resource "azurerm_postgresql_flexible_server" "main" {
  count = local.enabled

  name                = "${local.prefix}-database-${random_id.suffix[0].hex}"
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = local.settings.engine_version
  sku_name            = local.sku_name
  storage_mb          = local.storage_mb

  delegated_subnet_id           = var.subnet_id
  private_dns_zone_id           = azurerm_private_dns_zone.database[0].id
  public_network_access_enabled = false

  administrator_login               = local.settings.username
  administrator_password_wo         = ephemeral.random_password.administrator[0].result
  administrator_password_wo_version = 1

  backup_retention_days        = local.backup_retention_days
  geo_redundant_backup_enabled = false

  tags = local.tags

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.database,
    azurerm_subnet_network_security_group_association.database,
  ]

  lifecycle {
    ignore_changes = [zone]

    precondition {
      condition     = local.sku_name != null
      error_message = "The catalog has no azure db_size mapping for ${lookup(local.settings, "size", "micro")}."
    }

    precondition {
      condition     = var.subnet_id != null
      error_message = "A managed database on Azure needs network.database_subnet_cidrs: PostgreSQL Flexible Server only runs in a subnet delegated to it."
    }
  }
}

resource "azurerm_postgresql_flexible_server_database" "application" {
  count = local.enabled

  name      = local.settings.database_name
  server_id = azurerm_postgresql_flexible_server.main[0].id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  count = local.enabled

  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.main[0].id
  value     = "PG_CRON"
}

resource "azurerm_postgresql_flexible_server_configuration" "cron_database" {
  count = local.enabled

  name      = "cron.database_name"
  server_id = azurerm_postgresql_flexible_server.main[0].id
  value     = local.settings.database_name
}
