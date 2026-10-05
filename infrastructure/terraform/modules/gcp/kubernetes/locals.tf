locals {
  cloud    = "gcp"
  default  = lookup(var.config, "default_cloud", "")
  prefix   = "${var.config.name_prefix}-${var.config.environment}"
  token    = lookup(var.config, "default_region", "")
  region   = lookup(lookup(var.config.catalog.region, local.cloud, {}), local.token, null)
  zone     = lookup(lookup(var.config.catalog.zone, local.cloud, {}), local.token, null)
  project  = lookup(lookup(var.config, "gcp", {}), "project_id", null)
  settings = lookup(var.config, "kubernetes", {})

  enabled = lookup(local.settings, "managed", false) && lookup(local.settings, "cloud", local.default) == local.cloud
  count   = local.enabled ? 1 : 0
  name    = "${local.prefix}-gke"

  vpc_cidr     = var.config.network.vpc_cidr
  node_cidr    = lookup(local.settings, "node_subnet_cidr", cidrsubnet(local.vpc_cidr, 8, 2))
  pod_cidr     = lookup(local.settings, "pod_cidr", "10.40.0.0/16")
  service_cidr = lookup(local.settings, "service_cidr", "10.41.0.0/20")
  master_cidr  = lookup(local.settings, "control_plane_cidr", "172.16.0.0/28")

  machine_type = lookup(lookup(var.config.catalog.size, local.cloud, {}), lookup(local.settings, "node_size", "medium"), null)
  disk_type    = lookup(lookup(var.config.catalog.disk_type, local.cloud, {}), "balanced", "pd-balanced")
  node_count   = lookup(local.settings, "node_count", 3)
  disk_gb      = lookup(local.settings, "node_disk_gb", 30)
  version      = lookup(local.settings, "version", null)

  # The API answers on a public address, but only to these: where Ansible,
  # Helm and kubectl run. By default the same addresses the bastion admits.
  api_cidrs = lookup(local.settings, "api_allowed_cidrs", distinct(flatten([
    for name, vm in var.config.vms : lookup(vm, "allowed_cidrs", []) if vm.role == "bastion"
  ])))

  node_tag = "${local.prefix}-gke-node"

  labels = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}
