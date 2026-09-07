locals {
  cloud     = "aws"
  default   = lookup(var.config, "default_cloud", "")
  prefix    = "${var.config.name_prefix}-${var.config.environment}"
  settings  = lookup(var.config, "monitoring", {})
  enabled   = length(var.instance_ids) > 0 && length(local.settings) > 0 ? 1 : 0
  log_group = "/${var.config.name_prefix}/${var.config.environment}/docker"
}
