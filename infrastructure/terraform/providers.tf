# Only the budget needs this: it belongs to the billing account, so the request
# carries no project for Google to bill the API quota to and is refused.
provider "google" {
  project               = lookup(lookup(local.config, "gcp", {}), "project_id", null)
  billing_project       = lookup(lookup(local.config, "gcp", {}), "project_id", null)
  user_project_override = true
}

# Terraform configures every provider in the root module, used or not, and the
# AWS one asks STS who it is before doing anything. Without an AWS VM nothing
# here talks to AWS, so stale or missing credentials must not stop a plan for
# the other clouds.
locals {
  aws_in_use = anytrue([
    for vm in values(local.config.vms) : lookup(vm, "cloud", lookup(local.config, "default_cloud", "")) == "aws"
  ])
}

provider "aws" {
  skip_credentials_validation = !local.aws_in_use
  skip_requesting_account_id  = !local.aws_in_use

  region = coalesce(
    lookup(lookup(local.config.catalog.region, "aws", {}), lookup(local.config, "default_region", ""), null),
    "us-east-1",
  )
}

provider "azurerm" {
  features {}

  subscription_id = lookup(lookup(local.config, "azure", {}), "subscription_id", null)
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
