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

  # The cloud controller puts an internal load balancer only into subnets that
  # carry the internal-elb role, and only the nodes' own zone gets it.
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

# The internet-facing load balancer goes into the public management subnet,
# next to the bastion and the NAT gateway.
resource "aws_ec2_tag" "public_elb_role" {
  for_each = local.enabled ? {
    "kubernetes.io/role/elb"              = "1"
    "kubernetes.io/cluster/${local.name}" = "shared"
  } : {}

  resource_id = var.subnets["management"]
  key         = each.key
  value       = each.value
}
