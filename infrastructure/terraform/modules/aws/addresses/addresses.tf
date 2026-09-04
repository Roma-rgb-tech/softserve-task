locals {
  tags = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}

resource "aws_eip" "public" {
  for_each = local.public_vms

  domain   = "vpc"
  instance = var.instance_ids[each.key]

  tags = merge(local.tags, { Name = "${local.prefix}-${each.key}-ip", role = each.value.role })
}
