locals {
  cloud    = "azure"
  default  = lookup(var.config, "default_cloud", "")
  prefix   = "${var.config.name_prefix}-${var.config.environment}"
  selected = { for n, vm in var.config.vms : n => vm if lookup(vm, "cloud", local.default) == local.cloud }
  enabled  = length(local.selected) > 0
  operator = sort(keys(var.config.ssh_users))[0]

  tags = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}
