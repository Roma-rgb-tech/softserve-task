resource "aws_sns_topic" "alerts" {
  count = local.enabled

  name = "${local.prefix}-alerts"
  tags = local.tags
}

resource "aws_sns_topic_subscription" "email" {
  count = local.enabled == 1 ? length(local.emails) : 0

  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = local.emails[count.index]
}
