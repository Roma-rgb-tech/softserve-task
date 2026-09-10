locals {
  panels = [
    { title = "CPU utilisation, %", namespace = "AWS/EC2", metric = "CPUUtilization", stat = "Average" },
    { title = "Memory used, %", namespace = "CWAgent", metric = "mem_used_percent", stat = "Average" },
    { title = "Disk used, %", namespace = "CWAgent", metric = "disk_used_percent", stat = "Maximum" },
  ]

  per_instance = [
    for index, panel in local.panels : {
      type   = "metric"
      x      = index * 8
      y      = 0
      width  = 8
      height = 7

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
}

resource "aws_cloudwatch_dashboard" "overview" {
  count = local.enabled

  dashboard_name = "${local.prefix}-overview"
  dashboard_body = jsonencode({
    widgets = local.per_instance
  })
}
