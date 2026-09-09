locals {
  cloud    = "aws"
  default  = lookup(var.config, "default_cloud", "")
  prefix   = "${var.config.name_prefix}-${var.config.environment}"
  settings = lookup(var.config, "database", {})
  in_use   = anytrue([for vm in var.config.vms : lookup(vm, "cloud", local.default) == local.cloud])

  database_cidrs = lookup(var.config.network, "database_subnet_cidrs", [])

  enabled = local.in_use && lookup(local.settings, "managed", false) && length(local.database_cidrs) > 0 ? 1 : 0

  instance_class = lookup(lookup(var.config.catalog, "db_size", {}), local.cloud, {})[lookup(local.settings, "size", "micro")]
  port           = var.config.service_ports.postgresql

  clients = ["fetcher", "history", "ui", "infra"]

  tags = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}
