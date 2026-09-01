resource "aws_security_group" "bastion" {
  count = local.network_count

  name        = "${local.resource_prefix}-bastion"
  description = "Bastion host"
  vpc_id      = aws_vpc.main[0].id

  tags = merge(local.tags, { Name = "${local.resource_prefix}-bastion" })
}

resource "aws_security_group" "infra" {
  count = local.network_count

  name        = "${local.resource_prefix}-infra"
  description = "Database workload"
  vpc_id      = aws_vpc.main[0].id

  tags = merge(local.tags, { Name = "${local.resource_prefix}-infra" })
}

resource "aws_security_group" "history" {
  count = local.network_count

  name        = "${local.resource_prefix}-history"
  description = "History workload"
  vpc_id      = aws_vpc.main[0].id

  tags = merge(local.tags, { Name = "${local.resource_prefix}-history" })
}

resource "aws_security_group" "fetcher" {
  count = local.network_count

  name        = "${local.resource_prefix}-fetcher"
  description = "Fetcher workload"
  vpc_id      = aws_vpc.main[0].id

  tags = merge(local.tags, { Name = "${local.resource_prefix}-fetcher" })
}

resource "aws_security_group" "ui" {
  count = local.network_count

  name        = "${local.resource_prefix}-ui"
  description = "UI workload"
  vpc_id      = aws_vpc.main[0].id

  tags = merge(local.tags, { Name = "${local.resource_prefix}-ui" })
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(local.has_bastion ? local.bastion_cidrs : [])

  security_group_id = aws_security_group.bastion[0].id
  cidr_ipv4         = each.value
  from_port         = local.bastion_ssh_port
  to_port           = local.bastion_ssh_port
  ip_protocol       = "tcp"
  description       = "Operator SSH to the bastion"

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_bootstrap" {
  for_each = toset(
    local.has_bastion && var.enable_bastion_ssh_bootstrap && local.bastion_ssh_port != 22
    ? local.bastion_cidrs
    : []
  )

  security_group_id = aws_security_group.bastion[0].id
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "Temporary bootstrap SSH to the bastion"

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "workload_ssh" {
  for_each = local.enabled ? local.workload_groups : {}

  security_group_id            = each.value
  referenced_security_group_id = aws_security_group.bastion[0].id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  description                  = "SSH from the bastion"

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "ui_web" {
  for_each = local.enabled ? toset(local.ui_public_ports) : toset([])

  security_group_id = aws_security_group.ui[0].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  ip_protocol       = "tcp"
  description       = "Public HTTPS to the UI"

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "history_api" {
  count = local.network_count

  security_group_id            = aws_security_group.history[0].id
  referenced_security_group_id = aws_security_group.ui[0].id
  from_port                    = local.config.service_ports.history_api
  to_port                      = local.config.service_ports.history_api
  ip_protocol                  = "tcp"
  description                  = "History API from the UI"

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "postgresql" {
  for_each = local.enabled ? {
    fetcher = aws_security_group.fetcher[0].id
    history = aws_security_group.history[0].id
    ui      = aws_security_group.ui[0].id
  } : {}

  security_group_id            = aws_security_group.infra[0].id
  referenced_security_group_id = each.value
  from_port                    = local.config.service_ports.postgresql
  to_port                      = local.config.service_ports.postgresql
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from ${each.key}"

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "allow_all" {
  for_each = local.security_groups

  security_group_id = each.value
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Egress through the NAT gateway"

  tags = local.tags
}
