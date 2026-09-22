locals {
  cloud    = "azure"
  default  = lookup(var.config, "default_cloud", "")
  prefix   = "${var.config.name_prefix}-${var.config.environment}"
  selected = { for n, vm in var.config.vms : n => vm if lookup(vm, "cloud", local.default) == local.cloud }
  enabled  = length(local.selected) > 0
  managed  = lookup(lookup(var.config, "database", {}), "managed", false)
  cached   = lookup(lookup(var.config, "sessions", {}), "backend", "postgresql") == "redis"
  tailnet  = contains(keys(var.config), "tailscale")

  remote_cidrs = [
    for cloud, network in lookup(var.config.network, "clouds", {}) :
    network.vpc_cidr if cloud != local.cloud && contains(distinct([for vm in var.config.vms : lookup(vm, "cloud", local.default)]), cloud)
  ]

  tags = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}
