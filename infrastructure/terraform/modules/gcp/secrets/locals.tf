locals {
  cloud  = "gcp"
  config = var.config

  default_cloud = lookup(local.config, "default_cloud", "")

  selected = {
    for name, vm in local.config.vms : name => vm
    if lookup(vm, "cloud", local.default_cloud) == local.cloud
  }

  labels = merge(
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

  workload_secret_pairs = flatten([
    for name, vm in local.secret_reading_vms : [
      for secret_id in distinct(values(vm.secret_mappings)) : {
        vm_name   = name
        secret_id = secret_id
      }
    ]
  ])

  version_managers = lookup(lookup(local.config, "gcp", {}), "secret_version_managers", [])

  secret_version_writers = {
    for pair in setproduct(sort(local.secret_ids), local.version_managers) :
    "${pair[0]}/${pair[1]}" => {
      secret_id = pair[0]
      member    = pair[1]
    }
  }
}
