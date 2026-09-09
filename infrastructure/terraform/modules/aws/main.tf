module "network" {
  source = "./network"

  config = var.config
}

module "routing" {
  source = "./routing"

  config              = var.config
  vpc_id              = module.network.vpc_id
  subnets             = module.network.subnets
  internet_gateway_id = module.network.internet_gateway_id
}

module "firewall" {
  source = "./firewall"

  config = var.config
  vpc_id = module.network.vpc_id
}

module "iam" {
  source = "./iam"

  config = var.config
}

module "vm" {
  source = "./vm"

  config             = var.config
  subnets            = module.network.subnets
  security_groups    = module.firewall.security_groups
  instance_profiles  = module.iam.instance_profiles
  runtime_identities = module.iam.runtime_identities
  key_name           = module.iam.key_name
}

module "addresses" {
  source = "./addresses"

  config       = var.config
  instance_ids = module.vm.instance_ids
}

module "secrets" {
  source = "./secrets"

  config             = var.config
  runtime_identities = module.iam.runtime_identities
}

module "monitoring" {
  source = "./monitoring"

  config       = var.config
  instance_ids = module.vm.instance_ids
}

module "database" {
  source = "./database"

  config          = var.config
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.database_subnet_ids
  security_groups = module.firewall.security_groups
}
