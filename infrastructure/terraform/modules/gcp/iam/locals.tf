locals {
  cloud     = "gcp"
  default   = lookup(var.config, "default_cloud", "")
  prefix    = "${var.config.name_prefix}-${var.config.environment}"
  project   = lookup(lookup(var.config, "gcp", {}), "project_id", null)
  monitored = length(lookup(var.config, "monitoring", {})) > 0
  selected  = { for n, vm in var.config.vms : n => vm if lookup(vm, "cloud", local.default) == local.cloud }
}
