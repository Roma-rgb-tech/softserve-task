module "network" {
  source = "./network"

  config = local.host_config
}

module "routing" {
  source = "./routing"

  config             = local.host_config
  network_id         = module.network.network_id
  workload_subnet_id = module.network.workload_subnet_id
}

module "firewall" {
  source = "./firewall"

  config     = local.host_config
  network_id = module.network.network_id
}

module "addresses" {
  source = "./addresses"

  config = local.host_config
}

module "iam" {
  source = "./iam"

  config = local.host_config
}

module "vm" {
  source = "./vm"

  config             = local.host_config
  subnets            = module.network.subnets
  runtime_identities = module.iam.runtime_identities
  public_ips         = module.addresses.public_ips
}

module "secrets" {
  source = "./secrets"

  config             = local.host_config
  cluster_secret_ids = local.cluster_secret_ids
  runtime_identities = module.iam.runtime_identities
}

module "monitoring" {
  source = "./monitoring"

  config = local.host_config
}

module "database" {
  source = "./database"

  config     = local.host_config
  network_id = module.network.network_id
  subnet_id  = module.network.database_subnet_id
}

module "tailnet" {
  source = "./tailnet"

  config     = local.host_config
  network_id = module.network.network_id
  next_hop   = module.vm.bastion_instance
}

module "kubernetes" {
  source = "./kubernetes"

  config     = var.config
  network_id = module.network.network_id
}
