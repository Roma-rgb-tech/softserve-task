locals {
  cloud  = "gcp"
  config = var.config

  default_cloud = lookup(local.config, "default_cloud", "")

  selected = {
    for name, vm in local.config.vms : name => vm
    if lookup(vm, "cloud", local.default_cloud) == local.cloud
  }

  enabled = length(local.selected) > 0

  required_apis = [
    "compute.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
  ]
}
