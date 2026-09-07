data "aws_partition" "current" {}

# Tighter than the managed CloudWatchAgentServerPolicy, which allows publishing
# into any namespace and reading every parameter in Systems Manager. The agent
# here needs one namespace, one log group and its own instance tags.
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

  # The agent reads the instance tags to label what it publishes. Describing a
  # tag is not scopable to one instance in IAM.
  statement {
    effect    = "Allow"
    actions   = ["ec2:DescribeTags"]
    resources = ["*"]
  }
}

# Filtered rather than a conditional on the whole map: the VM objects are not
# all the same shape - only the bastion carries ssh_port, only the UI carries
# public_endpoint - so Terraform cannot unify them with an empty map.
resource "aws_iam_role_policy" "telemetry" {
  for_each = { for name, vm in local.selected : name => vm if local.monitored }

  name   = "${local.prefix}-${each.key}-telemetry"
  role   = aws_iam_role.workload[each.key].name
  policy = data.aws_iam_policy_document.telemetry[0].json
}
