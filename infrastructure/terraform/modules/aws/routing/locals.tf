locals {
  cloud   = "aws"
  default = lookup(var.config, "default_cloud", "")
  prefix  = "${var.config.name_prefix}-${var.config.environment}"
  enabled = anytrue([for vm in var.config.vms : lookup(vm, "cloud", local.default) == local.cloud])
  count   = local.enabled ? 1 : 0
}
