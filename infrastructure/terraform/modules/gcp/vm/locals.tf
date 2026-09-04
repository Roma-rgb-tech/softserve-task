locals {
  cloud      = "gcp"
  default    = lookup(var.config, "default_cloud", "")
  prefix     = "${var.config.name_prefix}-${var.config.environment}"
  token      = lookup(var.config, "default_region", "")
  zone       = lookup(lookup(var.config.catalog.zone, local.cloud, {}), local.token, null)
  project_id = lookup(lookup(var.config, "gcp", {}), "project_id", "")
  selected   = { for n, vm in var.config.vms : n => vm if lookup(vm, "cloud", local.default) == local.cloud }
}
