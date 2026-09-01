resource "aws_eip" "nat" {
  count = local.network_count

  domain = "vpc"

  tags = merge(local.tags, { Name = "${local.resource_prefix}-nat-ip" })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count = local.network_count

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.management[0].id

  tags = merge(local.tags, { Name = "${local.resource_prefix}-nat" })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "management" {
  count = local.network_count

  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = merge(local.tags, { Name = "${local.resource_prefix}-management-rt" })
}

resource "aws_route_table" "workload" {
  count = local.network_count

  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[0].id
  }

  tags = merge(local.tags, { Name = "${local.resource_prefix}-workload-rt" })
}

resource "aws_route_table_association" "management" {
  count = local.network_count

  subnet_id      = aws_subnet.management[0].id
  route_table_id = aws_route_table.management[0].id
}

resource "aws_route_table_association" "workload" {
  count = local.network_count

  subnet_id      = aws_subnet.workload[0].id
  route_table_id = aws_route_table.workload[0].id
}
