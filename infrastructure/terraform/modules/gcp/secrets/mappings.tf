locals {
  readers = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", local.default) == local.cloud
    && vm.role != "bastion" && length(vm.secret_mappings) > 0
  }

  secret_ids = distinct(flatten([for name, vm in local.readers : values(vm.secret_mappings)]))

  access_pairs = merge([
    for name, vm in local.readers : {
      for id in distinct(values(vm.secret_mappings)) :
      "${name}/${id}" => { vm_name = name, secret_id = id }
    }
  ]...)

  managers = lookup(lookup(var.config, "gcp", {}), "secret_version_managers", [])

  version_writers = {
    for pair in setproduct(sort(local.secret_ids), local.managers) :
    "${pair[0]}/${pair[1]}" => { secret_id = pair[0], member = pair[1] }
  }
}
