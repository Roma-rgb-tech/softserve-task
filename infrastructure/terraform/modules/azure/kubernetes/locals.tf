locals {
  cloud    = "azure"
  default  = lookup(var.config, "default_cloud", "")
  prefix   = "${var.config.name_prefix}-${var.config.environment}"
  settings = lookup(var.config, "kubernetes", {})

  enabled = lookup(local.settings, "managed", false) && lookup(local.settings, "cloud", local.default) == local.cloud
  count   = local.enabled ? 1 : 0
  name    = "${local.prefix}-aks"

  vpc_cidr     = var.config.network.vpc_cidr
  node_cidr    = lookup(local.settings, "node_subnet_cidr", cidrsubnet(local.vpc_cidr, 8, 10))
  pod_cidr     = lookup(local.settings, "pod_cidr", "10.40.0.0/16")
  service_cidr = lookup(local.settings, "service_cidr", "10.41.0.0/20")

  vm_size    = lookup(lookup(var.config.catalog.size, local.cloud, {}), lookup(local.settings, "node_size", "medium"), null)
  node_count = lookup(local.settings, "node_count", 3)
  disk_gb    = lookup(local.settings, "node_disk_gb", 30)
  version    = lookup(local.settings, "version", null)

  # GitOps on AKS reads the application secrets with External Secrets, as the
  # identity below, through the service account the oilscope-secrets chart
  # creates in the application namespace.
  external_secrets           = local.enabled && lookup(lookup(local.settings, "gitops", {}), "enabled", false)
  external_secrets_namespace = lookup(lookup(var.config, "cluster", {}), "namespace", "oilscope")
  external_secrets_account   = "oilscope-secrets"

  api_cidrs = lookup(local.settings, "api_allowed_cidrs", distinct(flatten([
    for name, vm in var.config.vms : lookup(vm, "allowed_cidrs", []) if vm.role == "bastion"
  ])))

  tags = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}
