locals {
  cloud   = "aws"
  default = lookup(var.config, "default_cloud", "")
  prefix  = "${var.config.name_prefix}-${var.config.environment}"
  zone    = lookup(lookup(var.config.catalog.zone, local.cloud, {}), lookup(var.config, "default_region", ""), null)
  count   = anytrue([for vm in var.config.vms : lookup(vm, "cloud", local.default) == local.cloud]) ? 1 : 0
}
