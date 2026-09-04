resource "aws_secretsmanager_secret" "this" {
  for_each = toset(local.secret_ids)

  name        = each.value
  description = "Managed by Terraform from the project configuration"
  tags        = local.tags

  recovery_window_in_days = 7
}

data "aws_iam_policy_document" "workload_secret_access" {
  for_each = local.secret_reading_vms

  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]

    resources = [
      for secret_id in distinct(values(each.value.secret_mappings)) :
      aws_secretsmanager_secret.this[secret_id].arn
    ]
  }
}

resource "aws_iam_role_policy" "workload_secret_access" {
  for_each = local.secret_reading_vms

  name   = "${local.resource_prefix}-${each.key}-secret-access"
  role   = var.runtime_identities[each.key]
  policy = data.aws_iam_policy_document.workload_secret_access[each.key].json
}

data "aws_iam_policy_document" "version_adder" {
  for_each = toset(length(local.version_managers) > 0 ? local.secret_ids : [])

  statement {
    effect  = "Allow"
    actions = ["secretsmanager:PutSecretValue"]

    principals {
      type        = "AWS"
      identifiers = local.version_managers
    }

    resources = ["*"]
  }
}

resource "aws_secretsmanager_secret_policy" "version_adder" {
  for_each = toset(length(local.version_managers) > 0 ? local.secret_ids : [])

  secret_arn = aws_secretsmanager_secret.this[each.value].arn
  policy     = data.aws_iam_policy_document.version_adder[each.value].json

  lifecycle {
    precondition {
      condition = alltrue([
        for principal in local.version_managers :
        can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(root|user/.+|role/.+)$", principal))
      ])
      error_message = "Each aws.secret_version_managers entry must be an IAM ARN, for example arn:aws:iam::123456789012:user/name."
    }
  }
}
