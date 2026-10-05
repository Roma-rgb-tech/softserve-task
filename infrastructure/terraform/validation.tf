locals {
  declared_workspace = lookup(local.config, "workspace", "")

  requested_clouds = distinct([
    for name, vm in local.config.vms :
    lookup(vm, "cloud", lookup(local.config, "default_cloud", ""))
  ])

  kubernetes         = lookup(local.config, "kubernetes", {})
  managed_kubernetes = lookup(local.kubernetes, "managed", false)
  kubernetes_cloud   = lookup(local.kubernetes, "cloud", lookup(local.config, "default_cloud", ""))

  bastion_clouds = distinct([
    for name, vm in local.config.vms :
    lookup(vm, "cloud", lookup(local.config, "default_cloud", "")) if vm.role == "bastion"
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

    # The bastion is the tailnet's way into the cluster's internal load
    # balancer, and the managed cluster joins the bastion's network.
    precondition {
      condition     = !local.managed_kubernetes || contains(local.bastion_clouds, local.kubernetes_cloud)
      error_message = "kubernetes.cloud is ${local.kubernetes_cloud}, but no bastion is there (bastions: ${join(", ", local.bastion_clouds)}). Put the bastion in the cluster's cloud - set default_cloud, or the bastion's cloud key, to ${local.kubernetes_cloud}."
    }

    precondition {
      condition     = !local.managed_kubernetes || anytrue([for name, vm in local.config.vms : contains(["k3s_server", "k3s_agent"], vm.role) && length(lookup(vm, "secret_mappings", {})) > 0])
      error_message = "A managed cluster still reads its secrets through the secret_mappings of a k3s_server entry. Keep that entry in vms - Terraform skips the VM itself while kubernetes.managed is true."
    }
  }
}
