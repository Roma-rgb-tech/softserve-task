locals {
  cloud    = "azure"
  prefix   = "${var.config.name_prefix}-${var.config.environment}"
  settings = lookup(var.config, "monitoring", {})
  enabled  = length(var.vm_ids) > 0 && length(local.settings) > 0 ? 1 : 0
  watched  = local.enabled == 1 ? var.vm_ids : {}

  emails = lookup(local.settings, "alert_emails", [])
  cpu    = lookup(local.settings, "cpu_percent", 80)
  memory = lookup(local.settings, "memory_percent", 85)
  disk   = lookup(local.settings, "disk_percent", 85)
  errors = lookup(local.settings, "error_log_threshold", 5)
  budget = lookup(local.settings, "budget", {})

  tags = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}
