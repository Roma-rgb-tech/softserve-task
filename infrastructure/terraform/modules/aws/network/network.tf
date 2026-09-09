locals {
  tags = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}

resource "aws_vpc" "main" {
  count = local.count

  cidr_block           = var.config.network.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${local.prefix}-vpc" })
}

resource "aws_subnet" "management" {
  count = local.count

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = var.config.network.management_subnet_cidr
  availability_zone = local.zone

  map_public_ip_on_launch = false

  tags = merge(local.tags, { Name = "${local.prefix}-management" })
}

resource "aws_subnet" "workload" {
  count = local.count

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = var.config.network.workload_subnet_cidr
  availability_zone = local.zone

  map_public_ip_on_launch = false

  tags = merge(local.tags, { Name = "${local.prefix}-workload" })
}

resource "aws_internet_gateway" "main" {
  count = local.count

  vpc_id = aws_vpc.main[0].id

  tags = merge(local.tags, { Name = "${local.prefix}-igw" })
}

data "aws_availability_zones" "available" {
  count = local.count

  state = "available"
}

resource "aws_subnet" "database" {
  for_each = local.database_subnets

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.zone

  map_public_ip_on_launch = false

  tags = merge(local.tags, { Name = "${local.prefix}-database-${each.key}" })
}
