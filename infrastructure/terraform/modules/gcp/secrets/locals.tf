locals {
  cloud   = "gcp"
  default = lookup(var.config, "default_cloud", "")
}
