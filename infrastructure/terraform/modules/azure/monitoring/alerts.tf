resource "azurerm_monitor_metric_alert" "cpu" {
  for_each = local.watched

  name                = "${local.prefix}-${each.key}-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [each.value]
  description         = "Busy for five minutes straight. Check what is running before resizing anything: a stuck retry loop looks exactly like real load."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = local.cpu
  }

  action {
    action_group_id = azurerm_monitor_action_group.email[0].id
  }
}

resource "azurerm_monitor_metric_alert" "availability" {
  for_each = local.watched

  name                = "${local.prefix}-${each.key}-status"
  resource_group_name = var.resource_group_name
  scopes              = [each.value]
  description         = "${each.key} is not running, or Azure has stopped hearing from it."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "VmAvailabilityMetric"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.email[0].id
  }
}

locals {
  queries = {
    memory = {
      description = "Used memory has stayed high for five minutes. Published by the Azure Monitor agent; silence here means the agent stopped."
      threshold   = local.memory
      query       = <<-KQL
        Perf
        | where ObjectName == "Memory" and CounterName == "% Used Memory"
        | summarize value = avg(CounterValue) by Computer
      KQL
    }

    disk = {
      description = "A filesystem is filling up. Container images and logs are what usually fill it: docker system prune buys time, a bigger boot disk fixes it."
      threshold   = local.disk
      query       = <<-KQL
        Perf
        | where ObjectName == "Logical Disk" and CounterName == "% Used Space"
        | where InstanceName !startswith "/dev/loop" and InstanceName != "_Total"
        | summarize value = max(CounterValue) by Computer
      KQL
    }
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "threshold" {
  for_each = local.enabled == 1 ? local.queries : {}

  name                 = "${local.prefix}-${each.key}"
  resource_group_name  = var.resource_group_name
  location             = var.location
  scopes               = [azurerm_log_analytics_workspace.main[0].id]
  description          = each.value.description
  severity             = 2
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  tags                 = local.tags

  criteria {
    query                   = each.value.query
    time_aggregation_method = "Maximum"
    metric_measure_column   = "value"
    operator                = "GreaterThan"
    threshold               = each.value.threshold

    dimension {
      name     = "Computer"
      operator = "Include"
      values   = ["*"]
    }

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.email[0].id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "http_errors" {
  count = local.enabled

  name                 = "${local.prefix}-http-5xx"
  resource_group_name  = var.resource_group_name
  location             = var.location
  scopes               = [azurerm_log_analytics_workspace.main[0].id]
  description          = "The services are answering requests with server errors. The matching lines are in the Syslog table of ${azurerm_log_analytics_workspace.main[0].name}."
  severity             = 2
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  tags                 = local.tags

  criteria {
    query                   = <<-KQL
      Syslog
      | where SyslogMessage matches regex @'HTTP/1.1. 5[0-9][0-9]'
    KQL
    time_aggregation_method = "Count"
    operator                = "GreaterThanOrEqual"
    threshold               = local.errors

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.email[0].id]
  }
}
