locals {
  cloud      = "aws"
  default    = lookup(var.config, "default_cloud", "")
  prefix     = "${var.config.name_prefix}-${var.config.environment}"
  token      = lookup(var.config, "default_region", "")
  regions    = lookup(lookup(var.config, "aws", {}), "regions", [])
  needs_iops = ["io1", "io2"]
  selected   = { for n, vm in var.config.vms : n => vm if lookup(vm, "cloud", local.default) == local.cloud }
}
