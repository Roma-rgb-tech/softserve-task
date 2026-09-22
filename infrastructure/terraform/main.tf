module "gcp" {
  source = "./modules/gcp"

  config = local.cloud_config.gcp
}

module "aws" {
  source = "./modules/aws"

  config = local.cloud_config.aws
}

module "azure" {
  source = "./modules/azure"

  config = local.cloud_config.azure
}
