locals {
  labels = merge({
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
      tags          = [for role in vm.network_tags : "${local.prefix}-${role}"]
      labels        = merge(local.labels, lookup(vm, "labels", {}), { role = vm.role })
      startup       = lookup(lookup(vm, "ci", {}), "startup_script", null)
      commands      = lookup(lookup(vm, "ci", {}), "commands", [])

      extra_disks = [
        for disk in lookup(vm, "extra_disks", []) : merge(disk, {
          disk_type = lookup(lookup(local.catalog.disk_type, local.cloud, {}), disk.type, null)
        })
      ]
    })
  }

  extra_disks = merge([
    for name, vm in local.vms : {
      for disk in vm.extra_disks : "${name}/${disk.name}" => merge(disk, { vm = name })
    }
  ]...)

  ssh_keys = join("\n", [
    for user, key in var.config.ssh_users : "${user}:${trimspace(key)}"
  ])
}
