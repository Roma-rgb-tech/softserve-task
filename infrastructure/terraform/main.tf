module "gcp" {
  source = "./modules/gcp"

  config = local.config
}

module "aws" {
  source = "./modules/aws"

  config = local.config
}
