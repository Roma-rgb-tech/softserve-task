locals {
  cloud   = "aws"
  default = lookup(var.config, "default_cloud", "")
  prefix  = "${var.config.name_prefix}-${var.config.environment}"

  recovery_days = lookup(lookup(var.config, "aws", {}), "secret_recovery_days", 0)
}
