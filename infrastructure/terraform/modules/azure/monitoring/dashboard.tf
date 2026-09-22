locals {
  panels = [
    { title = "CPU utilisation, %", object = "Processor", counter = "% Processor Time", aggregate = "avg" },
    { title = "Memory used, %", object = "Memory", counter = "% Used Memory", aggregate = "avg" },
    { title = "Disk used, %", object = "Logical Disk", counter = "% Used Space", aggregate = "max" },
  ]

  workbook = {
    version = "Notebook/1.0"
    items = [
      for index, panel in local.panels : {
        type = 3
        name = "panel-${index}"
        content = {
          version                 = "KqlItem/1.0"
          title                   = panel.title
          query                   = "Perf | where ObjectName startswith \"${panel.object}\" and CounterName == \"${panel.counter}\" | where InstanceName !startswith \"/dev/loop\" | where ObjectName != \"Processor\" or InstanceName in (\"_Total\", \"total\") | summarize ${panel.aggregate}(CounterValue) by Computer, bin(TimeGenerated, 5m)"
          size                    = 0
          queryType               = 0
          resourceType            = "microsoft.operationalinsights/workspaces"
          crossComponentResources = [for id in azurerm_log_analytics_workspace.main[*].id : lower(id)]
          visualization           = "timechart"
          timeContext             = { durationMs = 21600000 }
        }
        customWidth = "33"
      }
    ]
  }
}

resource "random_uuid" "workbook" {
  count = local.enabled
}

resource "azurerm_application_insights_workbook" "overview" {
  count = local.enabled

  name                = random_uuid.workbook[0].result
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "${local.prefix} overview"
  source_id           = lower(azurerm_log_analytics_workspace.main[0].id)
  data_json           = jsonencode(local.workbook)
  tags                = local.tags
}
