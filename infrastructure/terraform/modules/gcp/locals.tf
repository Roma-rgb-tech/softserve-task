locals {
  cloud   = "gcp"
  default = lookup(var.config, "default_cloud", "")

  # With a managed cluster the k3s nodes are not built. Every module that
  # creates or grants something per VM is handed a configuration without them,
  # while their secret_mappings still name the containers the cluster needs,
  # so those containers are kept for Ansible to read from the controller.
  kubernetes         = lookup(var.config, "kubernetes", {})
  managed_kubernetes = lookup(local.kubernetes, "managed", false)
  node_roles         = ["k3s_server", "k3s_agent"]

  skipped_nodes = {
    for name, vm in var.config.vms : name => vm
    if local.managed_kubernetes && contains(local.node_roles, vm.role)
  }

  host_config = merge(var.config, {
    vms = { for name, vm in var.config.vms : name => vm if !contains(keys(local.skipped_nodes), name) }
  })

  cluster_secret_ids = sort(distinct(flatten([
    for name, vm in local.skipped_nodes : values(lookup(vm, "secret_mappings", {}))
    if lookup(vm, "cloud", local.default) == local.cloud
  ])))
}
