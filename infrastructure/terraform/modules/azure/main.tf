module "network" {
  source = "./network"

  config = local.host_config
}

module "routing" {
  source = "./routing"

  config              = local.host_config
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  subnets             = module.network.subnets
}

module "firewall" {
  source = "./firewall"

  config              = local.host_config
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  subnets             = module.network.subnets
}

module "iam" {
  source = "./iam"

  config              = local.host_config
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
}

module "addresses" {
  source = "./addresses"

  config              = local.host_config
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
}

module "vm" {
  source = "./vm"

  config              = local.host_config
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  subnets             = module.network.subnets
  security_groups     = module.firewall.security_groups
  public_ip_ids       = module.addresses.public_ip_ids
  identity_ids        = module.iam.identity_ids
  runtime_identities  = module.iam.runtime_identities
  admin_username      = module.iam.admin_username
  admin_public_key    = module.iam.admin_public_key

  depends_on = [module.routing]
}

module "secrets" {
  source = "./secrets"

  config              = local.host_config
  cluster_secret_ids  = local.cluster_secret_ids
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  principal_ids       = module.iam.principal_ids

  cluster_reader = {
    enabled      = module.kubernetes.external_secrets_reader.enabled
    principal_id = module.kubernetes.external_secrets_reader.principal_id
  }
}

module "monitoring" {
  source = "./monitoring"

  config              = local.host_config
  resource_group_name = module.network.resource_group_name
  resource_group_id   = module.network.resource_group_id
  location            = module.network.location
  vm_ids              = module.vm.vm_ids
  identity_ids        = module.iam.identity_ids
}

module "database" {
  source = "./database"

  config              = local.host_config
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  virtual_network_id  = module.network.virtual_network_id
  subnet_id           = module.network.database_subnet_id
  client_cidrs        = module.network.client_cidrs
}

module "tailnet" {
  source = "./tailnet"

  config              = local.host_config
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  subnets             = module.network.subnets
  next_hop            = module.vm.bastion_private_ip
}

module "kubernetes" {
  source = "./kubernetes"

  config               = var.config
  resource_group_name  = module.network.resource_group_name
  location             = module.network.location
  virtual_network_name = module.network.virtual_network_name
  virtual_network_id   = module.network.virtual_network_id
}
