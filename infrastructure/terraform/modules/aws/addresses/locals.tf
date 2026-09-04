locals {
  cloud   = "aws"
  default = lookup(var.config, "default_cloud", "")
  prefix  = "${var.config.name_prefix}-${var.config.environment}"

  public_vms = {
    for n, vm in var.config.vms : n => vm
    if lookup(vm, "cloud", local.default) == local.cloud && vm.assign_public_ip
  }
}
