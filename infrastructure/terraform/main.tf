module "gcp_base" {
  source = "./modules/gcp/base"

  config = local.config
}

module "gcp_network" {
  source = "./modules/gcp/network"

  config = local.config

  depends_on = [module.gcp_base]
}

module "gcp_vm" {
  source = "./modules/gcp/vm"

  config       = local.config
  subnets      = module.gcp_network.subnets
  network_tags = module.gcp_network.network_tags

  depends_on = [module.gcp_base]
}

module "gcp_secrets" {
  source = "./modules/gcp/secrets"

  config             = local.config
  runtime_identities = module.gcp_vm.runtime_identities

  depends_on = [module.gcp_base]
}

module "aws_network" {
  source = "./modules/aws/network"

  config = local.config
}

module "aws_vm" {
  source = "./modules/aws/vm"

  config          = local.config
  subnets         = module.aws_network.subnets
  security_groups = module.aws_network.security_groups
}

module "aws_secrets" {
  source = "./modules/aws/secrets"

  config             = local.config
  runtime_identities = module.aws_vm.runtime_identities
}
