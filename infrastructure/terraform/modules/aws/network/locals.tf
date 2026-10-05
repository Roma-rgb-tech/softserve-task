locals {
  cloud   = "aws"
  default = lookup(var.config, "default_cloud", "")
  prefix  = "${var.config.name_prefix}-${var.config.environment}"
  zone    = lookup(lookup(var.config.catalog.zone, local.cloud, {}), lookup(var.config, "default_region", ""), null)
  count   = anytrue([for vm in var.config.vms : lookup(vm, "cloud", local.default) == local.cloud]) ? 1 : 0

  managed_database = lookup(lookup(var.config, "database", {}), "managed", false) && lookup(lookup(var.config, "database", {}), "cloud", local.default) == local.cloud
  database_cidrs   = lookup(var.config.network, "database_subnet_cidrs", [])

  database_subnets = local.count == 0 || !local.managed_database ? {} : {
    for index, cidr in local.database_cidrs : tostring(index) => {
      cidr_block = cidr
      zone       = data.aws_availability_zones.available[0].names[index % length(data.aws_availability_zones.available[0].names)]
    }
  }

  # An EKS cluster's internet-facing load balancer goes into the public
  # management subnet, which the cloud controller finds by these tags. They
  # live here, on the subnet's own tags, so the two never fight over them.
  kubernetes = lookup(var.config, "kubernetes", {})
  eks        = lookup(local.kubernetes, "managed", false) && lookup(local.kubernetes, "cloud", local.default) == local.cloud
  eks_elb_tags = local.eks ? {
    "kubernetes.io/role/elb"                                                        = "1"
    "kubernetes.io/cluster/${var.config.name_prefix}-${var.config.environment}-eks" = "shared"
  } : {}
}
