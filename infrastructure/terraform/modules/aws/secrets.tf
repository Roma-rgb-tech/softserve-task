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
  role   = aws_iam_role.workload[each.key].name
  policy = data.aws_iam_policy_document.workload_secret_access[each.key].json
}

data "aws_iam_policy_document" "version_adder" {
  for_each = toset(length(var.secret_version_managers) > 0 ? local.secret_ids : [])

  statement {
    effect  = "Allow"
    actions = ["secretsmanager:PutSecretValue"]

    principals {
      type        = "AWS"
      identifiers = var.secret_version_managers
    }

    resources = ["*"]
  }
}

resource "aws_secretsmanager_secret_policy" "version_adder" {
  for_each = toset(length(var.secret_version_managers) > 0 ? local.secret_ids : [])

  secret_arn = aws_secretsmanager_secret.this[each.value].arn
  policy     = data.aws_iam_policy_document.version_adder[each.value].json
}
