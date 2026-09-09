locals {
  cloud      = "gcp"
  default    = lookup(var.config, "default_cloud", "")
  prefix     = "${var.config.name_prefix}-${var.config.environment}"
  settings   = lookup(var.config, "database", {})
  project_id = lookup(lookup(var.config, "gcp", {}), "project_id", "")
  token      = lookup(var.config, "default_region", "")
  region     = lookup(lookup(var.config.catalog.region, local.cloud, {}), local.token, null)
  in_use     = anytrue([for vm in var.config.vms : lookup(vm, "cloud", local.default) == local.cloud])

  database_cidrs = lookup(var.config.network, "database_subnet_cidrs", [])

  enabled = local.in_use && lookup(local.settings, "managed", false) && length(local.database_cidrs) > 0 ? 1 : 0

  flags = {
    "cloudsql.enable_pg_cron" = "on"
    "cron.database_name"      = lookup(local.settings, "database_name", "postgres")
  }

  tier = lookup(lookup(lookup(var.config.catalog, "db_size", {}), local.cloud, {}), lookup(local.settings, "size", "micro"), null)

  labels = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}
