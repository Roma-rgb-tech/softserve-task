locals {
  tags = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "workload" {
  for_each = local.selected

  name               = "${local.prefix}-${each.key}"
  description        = "Runtime identity for the ${local.prefix}-${each.key} workload VM"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(local.tags, { role = each.value.role })
}

resource "aws_iam_instance_profile" "workload" {
  for_each = local.selected

  name = "${local.prefix}-${each.key}"
  role = aws_iam_role.workload[each.key].name

  tags = merge(local.tags, { role = each.value.role })
}

resource "aws_key_pair" "operator" {
  count = local.enabled ? 1 : 0

  key_name   = "${local.prefix}-operator"
  public_key = trimspace(var.config.ssh_users[local.operator])

  tags = merge(local.tags, { Name = "${local.prefix}-operator" })
}
