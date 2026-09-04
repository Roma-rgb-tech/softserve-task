locals {
  cloud   = "aws"
  default = lookup(var.config, "default_cloud", "")
  prefix  = "${var.config.name_prefix}-${var.config.environment}"
}
