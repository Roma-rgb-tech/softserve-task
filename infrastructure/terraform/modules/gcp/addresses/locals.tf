locals {
  cloud   = "gcp"
  default = lookup(var.config, "default_cloud", "")
  prefix  = "${var.config.name_prefix}-${var.config.environment}"
  token   = lookup(var.config, "default_region", "")
  region  = lookup(lookup(var.config.catalog.region, local.cloud, {}), local.token, null)

  public_vms = {
    for n, vm in var.config.vms : n => vm
    if lookup(vm, "cloud", local.default) == local.cloud && vm.assign_public_ip
  }
}
