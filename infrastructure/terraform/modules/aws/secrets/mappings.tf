locals {
  readers = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", local.default) == local.cloud
    && vm.role != "bastion" && length(vm.secret_mappings) > 0
  }

  secret_ids = distinct(flatten([for name, vm in local.readers : values(vm.secret_mappings)]))
  managers   = lookup(lookup(var.config, "aws", {}), "secret_version_managers", [])
}
