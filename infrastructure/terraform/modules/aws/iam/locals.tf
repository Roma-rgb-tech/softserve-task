locals {
  cloud    = "aws"
  default  = lookup(var.config, "default_cloud", "")
  prefix   = "${var.config.name_prefix}-${var.config.environment}"
  selected = { for n, vm in var.config.vms : n => vm if lookup(vm, "cloud", local.default) == local.cloud }
  enabled  = length(local.selected) > 0
  operator = sort(keys(var.config.ssh_users))[0]
}
