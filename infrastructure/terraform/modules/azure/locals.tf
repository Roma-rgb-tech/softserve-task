locals {
  cloud   = "azure"
  default = lookup(var.config, "default_cloud", "")

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

  # The application secrets External Secrets copies into the cluster; the
  # platform's own (Cloudflare, Grafana) stay with Ansible and out of its reach.
  external_secrets_variables = ["GHCR_TOKEN", "POSTGRES_PASSWORD", "REDIS_PASSWORD", "OILPRICEAPI_KEY"]
  external_secret_ids = sort(distinct(flatten([
    for name, vm in local.skipped_nodes : [
      for variable, secret_id in lookup(vm, "secret_mappings", {}) : secret_id
      if contains(local.external_secrets_variables, variable)
    ]
    if lookup(vm, "cloud", local.default) == local.cloud
  ])))
}
