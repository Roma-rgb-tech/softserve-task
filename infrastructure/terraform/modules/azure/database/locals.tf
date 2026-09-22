locals {
  cloud    = "azure"
  default  = lookup(var.config, "default_cloud", "")
  prefix   = "${var.config.name_prefix}-${var.config.environment}"
  settings = lookup(var.config, "database", {})
  in_use   = contains(keys(var.config), local.cloud) || anytrue([for vm in var.config.vms : lookup(vm, "cloud", local.default) == local.cloud])

  database_cidrs = lookup(var.config.network, "database_subnet_cidrs", [])

  enabled = local.in_use && lookup(local.settings, "managed", false) && length(local.database_cidrs) > 0 ? 1 : 0

  sku_name = lookup(lookup(lookup(var.config.catalog, "db_size", {}), local.cloud, {}), lookup(local.settings, "size", "micro"), null)
  port     = var.config.service_ports.postgresql

  storage_sizes_mb = [32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4194304]
  requested_mb     = lookup(local.settings, "storage_gb", 32) * 1024
  storage_mb       = [for size in local.storage_sizes_mb : size if size >= local.requested_mb][0]

  backup_retention_days = max(7, min(35, lookup(local.settings, "backup_retention_days", 7)))

  tags = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}
