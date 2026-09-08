locals {
  panels = [
    { title = "CPU utilisation, %", namespace = "AWS/EC2", metric = "CPUUtilization", stat = "Average" },
    { title = "Memory used, %", namespace = "CWAgent", metric = "mem_used_percent", stat = "Average" },
    { title = "Disk used, %", namespace = "CWAgent", metric = "disk_used_percent", stat = "Maximum" },
    { title = "Failed status checks", namespace = "AWS/EC2", metric = "StatusCheckFailed", stat = "Maximum" },
  ]

  per_instance = [
    for index, panel in local.panels : {
      type   = "metric"
      x      = index % 2 * 12
      y      = floor(index / 2) * 6
      width  = 12
      height = 6

      properties = {
        title  = panel.title
        region = local.region
        stat   = panel.stat
        period = 300
        view   = "timeSeries"

        metrics = [
          for name in sort(keys(var.instance_ids)) :
          [panel.namespace, panel.metric, "InstanceId", var.instance_ids[name], { label = name }]
        ]
      }
    }
  ]

  errors_panel = {
    type   = "metric"
    x      = 0
    y      = length(local.panels) / 2 * 6
    width  = 24
    height = 6

    properties = {
      title   = "5xx responses"
      region  = local.region
      stat    = "Sum"
      period  = 300
      view    = "timeSeries"
      metrics = [["${var.config.name_prefix}/${var.config.environment}", "${local.prefix}-http-5xx"]]
    }
  }
}

resource "aws_cloudwatch_dashboard" "overview" {
  count = local.enabled

  dashboard_name = "${local.prefix}-overview"
  dashboard_body = jsonencode({
    widgets = concat(local.per_instance, [local.errors_panel])
  })
}
