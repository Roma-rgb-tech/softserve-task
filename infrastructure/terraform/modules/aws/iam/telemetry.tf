data "aws_partition" "current" {}

data "aws_iam_policy_document" "telemetry" {
  count = local.monitored ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["CWAgent"]
    }
  }

  statement {
    effect  = "Allow"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]

    resources = [
      "arn:${data.aws_partition.current.partition}:logs:*:*:log-group:/${var.config.name_prefix}/${var.config.environment}/*",
      "arn:${data.aws_partition.current.partition}:logs:*:*:log-group:/${var.config.name_prefix}/${var.config.environment}/*:*",
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["ec2:DescribeTags"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "telemetry" {
  for_each = { for name, vm in local.selected : name => vm if local.monitored }

  name   = "${local.prefix}-${each.key}-telemetry"
  role   = aws_iam_role.workload[each.key].name
  policy = data.aws_iam_policy_document.telemetry[0].json
}
