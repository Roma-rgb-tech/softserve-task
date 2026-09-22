locals {
  cloud   = "azure"
  default = lookup(var.config, "default_cloud", "")
  prefix  = "${var.config.name_prefix}-${var.config.environment}"
  zone    = lookup(lookup(var.config.catalog.zone, local.cloud, {}), lookup(var.config, "default_region", ""), null)

  public_vms = {
    for n, vm in var.config.vms : n => vm
    if lookup(vm, "cloud", local.default) == local.cloud && vm.assign_public_ip
  }

  tags = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}
