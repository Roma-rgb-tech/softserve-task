locals {
  tags = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}

resource "aws_secretsmanager_secret" "this" {
  for_each = toset(local.secret_ids)

  name        = each.value
  description = "Managed by Terraform from the project configuration"
  tags        = local.tags

  # Secrets Manager keeps a deleted secret for a recovery window and holds its
  # name reserved for the whole of it, so a destroyed environment cannot be
  # rebuilt under the same names until it expires. That is the right trade for
  # production and the wrong one for an environment that exists to be torn down,
  # so the window is only kept where losing a value would actually matter.
  recovery_window_in_days = var.config.environment == "prod" ? 30 : 0
}

data "aws_iam_policy_document" "workload_secret_access" {
  for_each = local.readers

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
  for_each = local.readers

  name   = "${local.prefix}-${each.key}-secret-access"
  role   = var.runtime_identities[each.key]
  policy = data.aws_iam_policy_document.workload_secret_access[each.key].json
}

data "aws_iam_policy_document" "version_adder" {
  for_each = toset(length(local.managers) > 0 ? local.secret_ids : [])

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:PutSecretValue",
      "secretsmanager:ListSecretVersionIds",
    ]

    principals {
      type        = "AWS"
      identifiers = local.managers
    }

    resources = ["*"]
  }
}

resource "aws_secretsmanager_secret_policy" "version_adder" {
  for_each = toset(length(local.managers) > 0 ? local.secret_ids : [])

  secret_arn = aws_secretsmanager_secret.this[each.value].arn
  policy     = data.aws_iam_policy_document.version_adder[each.value].json

  lifecycle {
    precondition {
      condition = alltrue([
        for principal in local.managers :
        can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(root|user/.+|role/.+)$", principal))
      ])
      error_message = "Each aws.secret_version_managers entry must be an IAM ARN, for example arn:aws:iam::123456789012:user/name."
    }
  }
}
