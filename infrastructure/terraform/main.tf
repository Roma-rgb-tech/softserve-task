module "gcp" {
  source = "./modules/gcp"

  config = local.config
}

module "aws" {
  source = "./modules/aws"

  config = local.config
}

module "azure" {
  source = "./modules/azure"

  config = local.config
}
