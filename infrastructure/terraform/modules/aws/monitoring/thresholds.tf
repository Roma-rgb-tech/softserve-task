locals {
  emails = lookup(local.settings, "alert_emails", [])
  topic  = aws_sns_topic.alerts[*].arn

  cpu    = lookup(local.settings, "cpu_percent", 80)
  memory = lookup(local.settings, "memory_percent", 85)
  disk   = lookup(local.settings, "disk_percent", 85)
  errors = lookup(local.settings, "error_log_threshold", 5)
  budget = lookup(local.settings, "budget", {})

  region = lookup(lookup(var.config.catalog.region, local.cloud, {}), lookup(var.config, "default_region", ""), null)

  tags = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}
