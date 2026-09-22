locals {
  cloud   = "azure"
  default = lookup(var.config, "default_cloud", "")
  prefix  = "${var.config.name_prefix}-${var.config.environment}"
  enabled = length(local.secret_ids) > 0 ? 1 : 0

  vault_prefix = trimsuffix(substr(local.prefix, 0, 13), "-")
  retention    = lookup(lookup(var.config, "azure", {}), "secret_recovery_days", 7)

  tags = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}
