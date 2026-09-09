module "network" {
  source = "./network"

  config = var.config
}

module "routing" {
  source = "./routing"

  config             = var.config
  network_id         = module.network.network_id
  workload_subnet_id = module.network.workload_subnet_id
}

module "firewall" {
  source = "./firewall"

  config     = var.config
  network_id = module.network.network_id
}

module "addresses" {
  source = "./addresses"

  config = var.config
}

module "iam" {
  source = "./iam"

  config = var.config
}

module "vm" {
  source = "./vm"

  config             = var.config
  subnets            = module.network.subnets
  runtime_identities = module.iam.runtime_identities
  public_ips         = module.addresses.public_ips
}

module "secrets" {
  source = "./secrets"

  config             = var.config
  runtime_identities = module.iam.runtime_identities
}

module "monitoring" {
  source = "./monitoring"

  config = var.config
}
