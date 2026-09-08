locals {
  endpoints = local.enabled == 1 && local.region == "us-east-1" ? {
    for name, vm in var.config.vms : name => sort(var.config.network.ui_public_ports)[0]
    if lookup(vm, "cloud", local.default) == local.cloud
    && lookup(vm, "public_endpoint", null) != null
    && lookup(vm, "assign_public_ip", false)
  } : {}
}

resource "aws_route53_health_check" "endpoint" {
  for_each = local.endpoints

  type              = "TCP"
  ip_address        = var.public_ips[each.key]
  port              = each.value
  request_interval  = 30
  failure_threshold = 3

  tags = merge(local.tags, { Name = "${local.prefix}-${each.key}" })
}

resource "aws_cloudwatch_metric_alarm" "endpoint" {
  for_each = aws_route53_health_check.endpoint

  alarm_name        = "${local.prefix}-${each.key}-endpoint"
  alarm_description = "The public endpoint on ${each.key} stopped answering the Route 53 checkers. The VM may still be up - this is the path through it that is broken."

  namespace   = "AWS/Route53"
  metric_name = "HealthCheckStatus"
  statistic   = "Minimum"
  dimensions  = { HealthCheckId = each.value.id }

  comparison_operator = "LessThanThreshold"
  threshold           = 1
  period              = 60
  evaluation_periods  = 3
  treat_missing_data  = "breaching"

  alarm_actions = local.topic
  ok_actions    = local.topic
  tags          = merge(local.tags, { Name = "${local.prefix}-${each.key}-endpoint" })
}
