resource "aws_eip" "nat" {
  count = local.count

  domain = "vpc"

  tags = merge(local.tags, { Name = "${local.resource_prefix}-nat-ip" })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count = local.count

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.management[0].id

  tags = merge(local.tags, { Name = "${local.resource_prefix}-nat" })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "this" {
  for_each = local.route_tables

  vpc_id = local.vpc_id

  dynamic "route" {
    for_each = each.value.routes

    content {
      cidr_block     = route.value.cidr_block
      gateway_id     = route.value.gateway_id
      nat_gateway_id = route.value.nat_gateway_id
    }
  }

  tags = merge(local.tags, { Name = "${local.resource_prefix}-${each.key}-rt" })
}

resource "aws_route_table_association" "this" {
  for_each = local.route_tables

  subnet_id      = each.value.subnet_id
  route_table_id = aws_route_table.this[each.key].id
}
