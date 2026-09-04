locals {
  cloud  = "aws"
  config = var.config

  default_cloud = lookup(local.config, "default_cloud", "")
  region_token  = lookup(local.config, "default_region", "")

  region = lookup(lookup(local.config.catalog.region, local.cloud, {}), local.region_token, null)

  selected = {
    for name, vm in local.config.vms : name => vm
    if lookup(vm, "cloud", local.default_cloud) == local.cloud
  }

  enabled = length(local.selected) > 0

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  regions = lookup(lookup(local.config, "aws", {}), "regions", [])

  tags = merge(
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
      cloud       = local.cloud
    },
    local.config.common_labels,
  )

  iops_required = ["io1", "io2"]

  vms = {
    for name, vm in local.selected : name => merge(vm, {
      machine_type = lookup(lookup(local.config.catalog.size, local.cloud, {}), vm.size, null)
      disk_type    = lookup(lookup(local.config.catalog.disk_type, local.cloud, {}), vm.boot_disk.type, null)
      image        = lookup(lookup(local.config.catalog.os, local.cloud, {}), vm.os, null)

      boot_disk_iops = lookup(vm.boot_disk, "iops", null)

      public_subnet = vm.role == "bastion" || vm.assign_public_ip

      tags = merge(local.tags, lookup(vm, "labels", {}), { role = vm.role })

      startup_script = lookup(lookup(vm, "ci", {}), "startup_script", null)
    })
  }

  public_vms = { for name, vm in local.vms : name => vm if vm.assign_public_ip }

  operator_user = sort(keys(local.config.ssh_users))[0]
  operator_key  = trimspace(local.config.ssh_users[local.operator_user])
}
