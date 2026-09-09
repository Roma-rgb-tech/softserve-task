locals {
  tags = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)

  catalog = var.config.catalog

  vms = {
    for name, vm in local.selected : name => merge(vm, {
      machine_type  = lookup(lookup(local.catalog.size, local.cloud, {}), vm.size, null)
      disk_type     = lookup(lookup(local.catalog.disk_type, local.cloud, {}), vm.boot_disk.type, null)
      image         = lookup(lookup(local.catalog.os, local.cloud, {}), vm.os, null)
      iops          = lookup(vm.boot_disk, "iops", null)
      public_subnet = vm.role == "bastion" || vm.assign_public_ip
      tags          = merge(local.tags, lookup(vm, "labels", {}), { role = vm.role })
      startup       = lookup(lookup(vm, "ci", {}), "startup_script", null)
      commands      = lookup(lookup(vm, "ci", {}), "commands", [])

      extra_disks = [
        for index, disk in lookup(vm, "extra_disks", []) : merge(disk, {
          disk_type   = lookup(lookup(local.catalog.disk_type, local.cloud, {}), disk.type, null)
          device_name = "/dev/sd${substr(local.device_letters, index, 1)}"
        })
      ]
    })
  }
}
