resource "azurerm_log_analytics_workspace" "main" {
  count = local.enabled

  name                = "${local.prefix}-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_monitor_data_collection_rule" "vms" {
  count = local.enabled

  name                = "${local.prefix}-vms"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "Linux"
  tags                = local.tags

  destinations {
    log_analytics {
      name                  = "workspace"
      workspace_resource_id = azurerm_log_analytics_workspace.main[0].id
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Syslog"]
    destinations = ["workspace"]
  }

  data_sources {
    performance_counter {
      name                          = "usage"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\Processor(*)\\% Processor Time",
        "\\Memory\\% Used Memory",
        "\\Logical Disk(*)\\% Used Space",
      ]
    }

    syslog {
      name           = "containers"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["daemon", "user"]
      log_levels     = ["*"]
    }
  }
}

resource "azurerm_virtual_machine_extension" "agent" {
  for_each = local.watched

  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = each.value
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true

  settings = jsonencode({
    authentication = {
      managedIdentity = {
        identifier-name  = "mi_res_id"
        identifier-value = var.identity_ids[each.key]
      }
    }
  })

  tags = local.tags
}

resource "azurerm_monitor_data_collection_rule_association" "vms" {
  for_each = local.watched

  name                    = "${local.prefix}-${each.key}"
  target_resource_id      = each.value
  data_collection_rule_id = azurerm_monitor_data_collection_rule.vms[0].id

  depends_on = [azurerm_virtual_machine_extension.agent]
}
