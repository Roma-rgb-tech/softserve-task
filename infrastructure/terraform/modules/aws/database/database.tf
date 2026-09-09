resource "aws_db_subnet_group" "main" {
  count = local.enabled

  name        = "${local.prefix}-database"
  description = "Subnets the managed database is reachable in"
  subnet_ids  = var.subnet_ids

  tags = merge(local.tags, { Name = "${local.prefix}-database" })
}

resource "aws_security_group" "database" {
  count = local.enabled

  name        = "${local.prefix}-database"
  description = "Managed PostgreSQL"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${local.prefix}-database" })
}

resource "aws_vpc_security_group_ingress_rule" "clients" {
  for_each = local.enabled == 1 ? toset(local.clients) : toset([])

  security_group_id            = aws_security_group.database[0].id
  referenced_security_group_id = var.security_groups[each.value]
  from_port                    = local.port
  to_port                      = local.port
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from ${each.value}"

  tags = local.tags
}

resource "aws_db_parameter_group" "main" {
  count = local.enabled

  name        = "${local.prefix}-database"
  family      = "postgres${local.settings.engine_version}"
  description = "Extensions the migrations expect"

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_cron"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "cron.database_name"
    value        = local.settings.database_name
    apply_method = "pending-reboot"
  }

  tags = merge(local.tags, { Name = "${local.prefix}-database" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "main" {
  count = local.enabled

  identifier     = "${local.prefix}-database"
  engine         = "postgres"
  engine_version = local.settings.engine_version
  instance_class = local.instance_class

  allocated_storage     = local.settings.storage_gb
  max_allocated_storage = local.settings.storage_gb * 2
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = local.settings.database_name
  username = local.settings.username
  port     = local.port

  manage_master_user_password = true

  parameter_group_name   = aws_db_parameter_group.main[0].name
  db_subnet_group_name   = aws_db_subnet_group.main[0].name
  vpc_security_group_ids = [aws_security_group.database[0].id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = lookup(local.settings, "backup_retention_days", 7)
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false
  apply_immediately           = true

  deletion_protection       = lookup(local.settings, "deletion_protection", false)
  skip_final_snapshot       = !lookup(local.settings, "deletion_protection", false)
  final_snapshot_identifier = lookup(local.settings, "deletion_protection", false) ? "${local.prefix}-database-final" : null

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = merge(local.tags, { Name = "${local.prefix}-database" })

  lifecycle {
    precondition {
      condition     = local.instance_class != null
      error_message = "The catalog has no aws db_size mapping for ${lookup(local.settings, "size", "micro")}."
    }

    precondition {
      condition     = length(var.subnet_ids) >= 2
      error_message = "A managed database on AWS needs at least two entries in network.database_subnet_cidrs: a DB subnet group must span two availability zones."
    }
  }
}
