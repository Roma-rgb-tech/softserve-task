locals {
  cloud   = "azure"
  default = lookup(var.config, "default_cloud", "")
  prefix  = "${var.config.name_prefix}-${var.config.environment}"
  enabled = anytrue([for vm in var.config.vms : lookup(vm, "cloud", local.default) == local.cloud])
  count   = local.enabled ? 1 : 0

  tags = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}
