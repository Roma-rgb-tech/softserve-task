resource "terraform_data" "config_validation" {
  input = sort(local.clouds)

  lifecycle {
    precondition {
      condition     = alltrue([for cloud in local.clouds : contains(keys(local.config.catalog.size), cloud)])
      error_message = "Every VM must target a cloud the catalog knows. Requested: ${join(", ", local.clouds)}. In the catalog: ${join(", ", keys(local.config.catalog.size))}."
    }
  }
}
