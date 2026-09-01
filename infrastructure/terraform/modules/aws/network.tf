resource "aws_vpc" "main" {
  count = local.network_count

  cidr_block           = local.config.network.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${local.resource_prefix}-vpc" })
}

resource "aws_subnet" "management" {
  count = local.network_count

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = local.config.network.management_subnet_cidr
  availability_zone = local.zone

  map_public_ip_on_launch = false

  tags = merge(local.tags, { Name = "${local.resource_prefix}-management" })
}

resource "aws_subnet" "workload" {
  count = local.network_count

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = local.config.network.workload_subnet_cidr
  availability_zone = local.zone

  map_public_ip_on_launch = false

  tags = merge(local.tags, { Name = "${local.resource_prefix}-workload" })
}

resource "aws_internet_gateway" "main" {
  count = local.network_count

  vpc_id = aws_vpc.main[0].id

  tags = merge(local.tags, { Name = "${local.resource_prefix}-igw" })
}
