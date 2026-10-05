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

    # The cluster's subnets are checked against the database's, which share
    # the same network.
    precondition {
      condition = !local.managed_kubernetes || length(setintersection(
        toset(lookup(local.config.network, "database_subnet_cidrs", [])),
        toset(compact([
          lookup(local.kubernetes, "node_subnet_cidr", ""),
          lookup(local.kubernetes, "node_secondary_subnet_cidr", ""),
        ])),
      )) == 0
      error_message = "kubernetes.node_subnet_cidr / node_secondary_subnet_cidr must not be one of network.database_subnet_cidrs."
    }

    # On AWS and Azure the managed database only admits the k3s nodes' security
    # group or subnet. Until it admits the managed cluster's too, the two do
    # not go together there.
    precondition {
      condition     = !local.managed_kubernetes || !lookup(lookup(local.config, "database", {}), "managed", false) || local.kubernetes_cloud == "gcp"
      error_message = "A managed database together with a managed cluster is only wired up on GCP so far. Keep database.managed false - the database then runs in the cluster as CloudNativePG."
    }

    precondition {
      condition     = !local.managed_kubernetes || anytrue([for name, vm in local.config.vms : contains(["k3s_server", "k3s_agent"], vm.role) && length(lookup(vm, "secret_mappings", {})) > 0])
      error_message = "A managed cluster still reads its secrets through the secret_mappings of a k3s_server entry. Keep that entry in vms - Terraform skips the VM itself while kubernetes.managed is true."
    }
  }
}
