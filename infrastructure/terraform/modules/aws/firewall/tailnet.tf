resource "aws_vpc_security_group_ingress_rule" "tailnet_forward" {
  count = local.has_bastion && local.tailnet ? 1 : 0

  security_group_id = local.group_ids["bastion"]
  cidr_ipv4         = var.config.network.vpc_cidr
  ip_protocol       = "-1"
  description       = "Traffic the workloads send to the other clouds, forwarded by the tailnet subnet router"

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "tailnet_direct" {
  count = local.has_bastion && local.tailnet ? 1 : 0

  security_group_id = local.group_ids["bastion"]
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 41641
  to_port           = 41641
  ip_protocol       = "udp"
  description       = "Direct WireGuard connections between tailnet nodes"

  tags = local.tags
}
