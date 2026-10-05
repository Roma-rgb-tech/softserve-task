locals {
  cloud    = "aws"
  default  = lookup(var.config, "default_cloud", "")
  prefix   = "${var.config.name_prefix}-${var.config.environment}"
  token    = lookup(var.config, "default_region", "")
  zone     = lookup(lookup(var.config.catalog.zone, local.cloud, {}), local.token, null)
  settings = lookup(var.config, "kubernetes", {})

  enabled = lookup(local.settings, "managed", false) && lookup(local.settings, "cloud", local.default) == local.cloud
  count   = local.enabled ? 1 : 0
  name    = "${local.prefix}-eks"

  # EKS asks for subnets in two zones for its control plane interfaces. The
  # nodes and both load balancers stay in the first, the bastion's zone, so a
  # load balancer never has a zone without a node behind it.
  vpc_cidr   = var.config.network.vpc_cidr
  node_cidrs = [lookup(local.settings, "node_subnet_cidr", cidrsubnet(local.vpc_cidr, 8, 2)), cidrsubnet(local.vpc_cidr, 8, 3)]
  other_zone = local.enabled ? one(slice([for zone in data.aws_availability_zones.available[0].names : zone if zone != local.zone], 0, 1)) : null

  node_subnets = local.enabled ? {
    primary   = { cidr = local.node_cidrs[0], zone = local.zone }
    secondary = { cidr = local.node_cidrs[1], zone = local.other_zone }
  } : {}

  service_cidr  = lookup(local.settings, "service_cidr", "10.41.0.0/20")
  instance_type = lookup(lookup(var.config.catalog.size, local.cloud, {}), lookup(local.settings, "node_size", "medium"), null)
  node_count    = lookup(local.settings, "node_count", 3)
  disk_gb       = lookup(local.settings, "node_disk_gb", 30)
  version       = lookup(local.settings, "version", null)

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
