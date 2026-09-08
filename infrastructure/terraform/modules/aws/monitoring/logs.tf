resource "aws_cloudwatch_log_group" "docker" {
  count = local.enabled

  name              = local.log_group
  retention_in_days = 30
  tags              = local.tags
}

resource "aws_cloudwatch_log_metric_filter" "http_errors" {
  count = local.enabled

  name           = "${local.prefix}-http-5xx"
  log_group_name = aws_cloudwatch_log_group.docker[0].name
  pattern        = "\"HTTP/1.1\\\" 5\""

  metric_transformation {
    name          = "${local.prefix}-http-5xx"
    namespace     = "${var.config.name_prefix}/${var.config.environment}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "http_errors" {
  count = local.enabled

  alarm_name        = "${local.prefix}-http-5xx"
  alarm_description = "The services are answering requests with server errors. The matching lines are in the ${local.log_group} log group."

  namespace   = aws_cloudwatch_log_metric_filter.http_errors[0].metric_transformation[0].namespace
  metric_name = aws_cloudwatch_log_metric_filter.http_errors[0].metric_transformation[0].name
  statistic   = "Sum"

  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = local.errors
  period              = 300
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = local.topic
  ok_actions    = local.topic
  tags          = merge(local.tags, { Name = "${local.prefix}-http-5xx" })
}
