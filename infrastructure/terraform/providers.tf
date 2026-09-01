provider "google" {
  project = lookup(lookup(local.config, "gcp", {}), "project_id", null)
}

provider "aws" {
  region = coalesce(
    lookup(lookup(local.config.catalog.region, "aws", {}), lookup(local.config, "default_region", ""), null),
    "us-east-1",
  )
}
