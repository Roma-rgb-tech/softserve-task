resource "aws_security_group" "this" {
  for_each = local.enabled ? local.security_group_descriptions : tomap({})

  name        = "${local.resource_prefix}-${each.key}"
  description = each.value
  vpc_id      = local.vpc_id

  tags = merge(local.tags, { Name = "${local.resource_prefix}-${each.key}" })
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.ingress_rules

  security_group_id            = local.group_ids[each.value.group]
  cidr_ipv4                    = each.value.cidr_ipv4
  referenced_security_group_id = each.value.source_group == null ? null : local.group_ids[each.value.source_group]
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  ip_protocol                  = "tcp"
  description                  = each.value.description

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "allow_all" {
  for_each = local.group_ids

  security_group_id = each.value
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Egress through the NAT gateway"

  tags = local.tags
}
