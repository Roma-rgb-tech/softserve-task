data "aws_availability_zones" "available" {
  count = local.count

  state = "available"
}

resource "aws_subnet" "nodes" {
  for_each = local.node_subnets

  vpc_id            = var.vpc_id
  cidr_block        = each.value.cidr
  availability_zone = each.value.zone

  map_public_ip_on_launch = false

  # The internal-elb role marks where internal load balancers may go; which
  # subnet each one actually uses is pinned by name in its Service annotation
  # (cluster_platform), because the cloud controller would otherwise also put
  # one into the second zone, where no node runs.
  tags = merge(local.tags, {
    Name                                  = "${local.prefix}-eks-${each.key}"
    "kubernetes.io/cluster/${local.name}" = "shared"
    }, each.key == "primary" ? {
    "kubernetes.io/role/internal-elb" = "1"
  } : {})
}

resource "aws_route_table_association" "nodes" {
  for_each = local.node_subnets

  subnet_id      = aws_subnet.nodes[each.key].id
  route_table_id = var.route_table_ids["workload"]
}
