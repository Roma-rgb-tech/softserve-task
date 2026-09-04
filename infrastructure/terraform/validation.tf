locals {
  requested_clouds = distinct([
    for name, vm in local.config.vms :
    lookup(vm, "cloud", lookup(local.config, "default_cloud", ""))
  ])
}

resource "terraform_data" "config_validation" {
  input = sort(local.requested_clouds)

  lifecycle {
    precondition {
      condition     = alltrue([for cloud in local.requested_clouds : contains(keys(local.config.catalog.size), cloud)])
      error_message = "Every VM must target a cloud the catalog knows. Requested: ${join(", ", local.requested_clouds)}. In the catalog: ${join(", ", keys(local.config.catalog.size))}."
    }
  }
}
