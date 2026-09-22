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
      public_subnet = vm.role == "bastion" || vm.assign_public_ip
      tags          = merge(local.tags, lookup(vm, "labels", {}), { role = vm.role })
      startup       = lookup(lookup(vm, "ci", {}), "startup_script", null)
      commands      = lookup(lookup(vm, "ci", {}), "commands", [])

      extra_disks = [
        for index, disk in lookup(vm, "extra_disks", []) : merge(disk, {
          disk_type = lookup(lookup(local.catalog.disk_type, local.cloud, {}), disk.type, null)
          lun       = index
        })
      ]
    })
  }

  images = {
    for name, vm in local.vms : name => vm.image == null ? null : split(":", vm.image)
  }

  extra_disks = merge([
    for name, vm in local.vms : {
      for disk in vm.extra_disks : "${name}/${disk.name}" => merge(disk, { vm = name })
    }
  ]...)

  group_memberships = merge([
    for name, vm in local.vms : {
      for role in vm.network_tags : "${name}/${role}" => { vm = name, role = role }
    }
  ]...)
}
