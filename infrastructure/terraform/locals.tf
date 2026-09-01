locals {
  config = jsondecode(file(var.project_config_path))

  clouds = distinct([
    for name, vm in local.config.vms :
    lookup(vm, "cloud", lookup(local.config, "default_cloud", ""))
  ])

  vms = merge(module.gcp.vms, module.aws.vms)
}
