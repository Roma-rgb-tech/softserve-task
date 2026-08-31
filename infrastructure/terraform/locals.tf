locals {
  config = jsondecode(file(var.project_config_path))

  cloud  = try(local.config.cloud, "")
  is_gcp = local.cloud == "gcp"
  is_aws = local.cloud == "aws"

  location = try(local.catalog.location[local.cloud][local.config.location], null)
  region   = try(local.location.region, null)
  zone     = try(local.location.zone, null)

  bastion_vm = local.config.vms.bastion
  workload_vms = {
    for name, vm in local.config.vms : name => vm
    if vm.role != "bastion"
  }

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  common_labels = merge(
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
    },
    local.config.common_labels,
  )

  vms = {
    for name, vm in local.config.vms : name => merge(vm, {
      machine_type   = try(local.catalog.size[local.cloud][vm.size], null)
      boot_disk_type = try(local.catalog.disk_type[local.cloud][vm.boot_disk.type], null)
      image          = try(local.catalog.os[local.cloud][vm.os], null)
    })
  }

  gcp_vms = { for name, vm in local.vms : name => vm if local.is_gcp }
  aws_vms = { for name, vm in local.vms : name => vm if local.is_aws }

  secret_reading_vms = {
    for name, vm in local.workload_vms : name => vm
    if length(vm.secret_mappings) > 0
  }

  gcp_secret_reading_vms = { for name, vm in local.secret_reading_vms : name => vm if local.is_gcp }
  aws_secret_reading_vms = { for name, vm in local.secret_reading_vms : name => vm if local.is_aws }
}
