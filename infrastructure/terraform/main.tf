module "gcp" {
  source = "./modules/gcp"

  config = local.config
}

module "aws" {
  source = "./modules/aws"

  config = local.config
}

module "cloudflare" {
  source = "./modules/cloudflare"

  config = local.config
  vms    = local.vms
}
