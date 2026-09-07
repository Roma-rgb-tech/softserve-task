# Every alarm publishes here and the topic fans out to the addresses. AWS sends
# each address a confirmation link first and delivers nothing until it is
# clicked, so a fresh environment has one manual step GCP does not.
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
