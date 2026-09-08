# Only the budget needs this: it belongs to the billing account, so the request
# carries no project for Google to bill the API quota to and is refused.
provider "google" {
  project               = lookup(lookup(local.config, "gcp", {}), "project_id", null)
  billing_project       = lookup(lookup(local.config, "gcp", {}), "project_id", null)
  user_project_override = true
}

provider "aws" {
  region = coalesce(
    lookup(lookup(local.config.catalog.region, "aws", {}), lookup(local.config, "default_region", ""), null),
    "us-east-1",
  )
}
