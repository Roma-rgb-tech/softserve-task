locals {
  tags = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}

resource "aws_eip" "nat" {
  count = local.count

  domain = "vpc"

  tags = merge(local.tags, { Name = "${local.prefix}-nat-ip" })
}

resource "aws_nat_gateway" "main" {
  count = local.count

  allocation_id = aws_eip.nat[0].id
  subnet_id     = var.subnets.management

  tags = merge(local.tags, { Name = "${local.prefix}-nat" })
}

resource "aws_route_table" "this" {
  for_each = local.route_tables

  vpc_id = var.vpc_id

  tags = merge(local.tags, { Name = "${local.prefix}-${each.key}-rt" })
}

resource "aws_route" "default" {
  for_each = local.route_tables

  route_table_id         = aws_route_table.this[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = each.value.gateway_id
  nat_gateway_id         = each.value.nat_gateway_id
}

resource "aws_route_table_association" "this" {
  for_each = local.route_tables

  subnet_id      = each.value.subnet_id
  route_table_id = aws_route_table.this[each.key].id
}
