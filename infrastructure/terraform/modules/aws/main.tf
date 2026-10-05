module "network" {
  source = "./network"

  config = local.host_config
}

module "routing" {
  source = "./routing"

  config              = local.host_config
  vpc_id              = module.network.vpc_id
  subnets             = module.network.subnets
  internet_gateway_id = module.network.internet_gateway_id
}

module "firewall" {
  source = "./firewall"

  config = local.host_config
  vpc_id = module.network.vpc_id
}

module "iam" {
  source = "./iam"

  config = local.host_config
}

module "vm" {
  source = "./vm"

  config             = local.host_config
  subnets            = module.network.subnets
  security_groups    = module.firewall.security_groups
  instance_profiles  = module.iam.instance_profiles
  runtime_identities = module.iam.runtime_identities
  key_name           = module.iam.key_name
}

module "addresses" {
  source = "./addresses"

  config       = local.host_config
  instance_ids = module.vm.instance_ids
}

module "secrets" {
  source = "./secrets"

  config             = local.host_config
  cluster_secret_ids = local.cluster_secret_ids
  runtime_identities = module.iam.runtime_identities
}

module "monitoring" {
  source = "./monitoring"

  config       = local.host_config
  instance_ids = module.vm.instance_ids
}

module "database" {
  source = "./database"

  config          = local.host_config
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.database_subnet_ids
  security_groups = module.firewall.security_groups
}

module "tailnet" {
  source = "./tailnet"

  config          = local.host_config
  route_table_ids = module.routing.route_table_ids
  next_hop        = module.vm.bastion_interface_id
}

module "kubernetes" {
  source = "./kubernetes"

  config          = var.config
  vpc_id          = module.network.vpc_id
  subnets         = module.network.subnets
  route_table_ids = module.routing.route_table_ids
}
