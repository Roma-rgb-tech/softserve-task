locals {
  cloud  = "aws"
  config = var.config

  default_cloud = lookup(local.config, "default_cloud", "")

  selected = {
    for name, vm in local.config.vms : name => vm
    if lookup(vm, "cloud", local.default_cloud) == local.cloud
  }

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  tags = merge(
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
      cloud       = local.cloud
    },
    local.config.common_labels,
  )

  secret_reading_vms = {
    for name, vm in local.selected : name => vm
    if vm.role != "bastion" && length(vm.secret_mappings) > 0
  }

  secret_ids = distinct(flatten([
    for name, vm in local.secret_reading_vms : values(vm.secret_mappings)
  ]))

  version_managers = lookup(lookup(local.config, "aws", {}), "secret_version_managers", [])
}
