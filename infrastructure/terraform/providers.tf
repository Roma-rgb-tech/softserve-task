
provider "google" {
  project = try(local.config.gcp.project_id, null)
  region  = local.is_gcp ? local.region : null
  zone    = local.is_gcp ? local.zone : null
}

provider "aws" {
  region = local.is_aws ? local.region : "us-east-1"

  default_tags {
    tags = local.common_labels
  }
}
