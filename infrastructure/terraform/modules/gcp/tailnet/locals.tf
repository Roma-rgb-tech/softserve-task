locals {
  cloud   = "gcp"
  default = lookup(var.config, "default_cloud", "")
  prefix  = "${var.config.name_prefix}-${var.config.environment}"
  enabled = contains(keys(var.config), "tailscale") && anytrue([for vm in var.config.vms : lookup(vm, "cloud", local.default) == local.cloud && vm.role == "bastion"])

  clouds = distinct([for vm in var.config.vms : lookup(vm, "cloud", local.default)])

  remote_cidrs = {
    for cloud, network in lookup(var.config.network, "clouds", {}) :
    cloud => network.vpc_cidr if cloud != local.cloud && contains(local.clouds, cloud)
  }
}
