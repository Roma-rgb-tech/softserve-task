locals {
  cloud   = "gcp"
  default = lookup(var.config, "default_cloud", "")
  prefix  = "${var.config.name_prefix}-${var.config.environment}"
  region  = lookup(lookup(var.config.catalog.region, local.cloud, {}), lookup(var.config, "default_region", ""), null)
  count   = anytrue([for vm in var.config.vms : lookup(vm, "cloud", local.default) == local.cloud]) ? 1 : 0
}
