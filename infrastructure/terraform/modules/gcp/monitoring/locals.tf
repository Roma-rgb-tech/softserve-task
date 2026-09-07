locals {
  cloud    = "gcp"
  default  = lookup(var.config, "default_cloud", "")
  prefix   = "${var.config.name_prefix}-${var.config.environment}"
  settings = lookup(var.config, "monitoring", {})
  in_use   = anytrue([for vm in var.config.vms : lookup(vm, "cloud", local.default) == local.cloud])
  enabled  = local.in_use && length(local.settings) > 0 ? 1 : 0
  log_id   = "docker"
}
