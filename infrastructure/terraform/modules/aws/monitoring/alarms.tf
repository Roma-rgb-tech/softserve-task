locals {
  metrics = {
    cpu = {
      namespace   = "AWS/EC2"
      metric      = "CPUUtilization"
      statistic   = "Average"
      threshold   = local.cpu
      description = "Busy for five minutes straight. Check what is running before resizing anything: a stuck retry loop looks exactly like real load."
    }

    memory = {
      namespace   = "CWAgent"
      metric      = "mem_used_percent"
      statistic   = "Average"
      threshold   = local.memory
      description = "Used memory has stayed high for five minutes. Published by the CloudWatch agent; silence here means the agent stopped."
    }

    disk = {
      namespace   = "CWAgent"
      metric      = "disk_used_percent"
      statistic   = "Maximum"
      threshold   = local.disk
      description = "A filesystem is filling up. Container images and logs are what usually fill it: docker system prune buys time, a bigger boot disk fixes it."
    }
  }

  targets = local.enabled == 1 ? {
    for pair in setproduct(sort(keys(var.instance_ids)), sort(keys(local.metrics))) :
    "${pair[0]}/${pair[1]}" => { vm = pair[0], metric = pair[1] }
  } : {}
}

resource "aws_cloudwatch_metric_alarm" "threshold" {
  for_each = local.targets

  alarm_name        = "${local.prefix}-${each.value.vm}-${each.value.metric}"
  alarm_description = local.metrics[each.value.metric].description

  namespace   = local.metrics[each.value.metric].namespace
  metric_name = local.metrics[each.value.metric].metric
  statistic   = local.metrics[each.value.metric].statistic
  dimensions  = { InstanceId = var.instance_ids[each.value.vm] }

  comparison_operator = "GreaterThanThreshold"
  threshold           = local.metrics[each.value.metric].threshold
  period              = 300
  evaluation_periods  = 1

  alarm_actions = local.topic
  ok_actions    = local.topic
  tags          = merge(local.tags, { Name = "${local.prefix}-${each.value.vm}-${each.value.metric}" })
}

resource "aws_cloudwatch_metric_alarm" "availability" {
  for_each = local.enabled == 1 ? var.instance_ids : {}

  alarm_name        = "${local.prefix}-${each.key}-status"
  alarm_description = "${each.key} is failing its EC2 status checks, or has stopped reporting them at all."

  namespace   = "AWS/EC2"
  metric_name = "StatusCheckFailed"
  statistic   = "Maximum"
  dimensions  = { InstanceId = each.value }

  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  period              = 60
  evaluation_periods  = 3
  treat_missing_data  = "breaching"

  alarm_actions = local.topic
  ok_actions    = local.topic
  tags          = merge(local.tags, { Name = "${local.prefix}-${each.key}-status" })
}
