locals {
  declared_workspace = lookup(local.config, "workspace", "")

  requested_clouds = distinct([
    for name, vm in local.config.vms :
    lookup(vm, "cloud", lookup(local.config, "default_cloud", ""))
  ])
}

resource "terraform_data" "config_validation" {
  input = sort(local.requested_clouds)

  lifecycle {
    precondition {
      condition     = local.declared_workspace == "" || local.declared_workspace == terraform.workspace
      error_message = "${basename(var.project_config_path)} belongs to workspace ${local.declared_workspace}, but this is workspace ${terraform.workspace}. Applying it here would rename every resource of ${terraform.workspace} onto ${local.config.name_prefix}-${local.config.environment}. Select the matching workspace, or point project_config_path at this workspace's configuration."
    }

    precondition {
      condition     = alltrue([for cloud in local.requested_clouds : contains(keys(local.config.catalog.size), cloud)])
      error_message = "Every VM must target a cloud the catalog knows. Requested: ${join(", ", local.requested_clouds)}. In the catalog: ${join(", ", keys(local.config.catalog.size))}."
    }
  }
}
