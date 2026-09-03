provider "google" {
  project = lookup(lookup(local.config, "gcp", {}), "project_id", null)
}

provider "aws" {
  region = coalesce(
    lookup(lookup(local.config.catalog.region, "aws", {}), lookup(local.config, "location", ""), null),
    "us-east-1",
  )

  default_tags {
    tags = merge(
      {
        application = local.config.name_prefix
        environment = local.config.environment
        managed_by  = "terraform"
      },
      local.config.common_labels,
    )
  }
}
