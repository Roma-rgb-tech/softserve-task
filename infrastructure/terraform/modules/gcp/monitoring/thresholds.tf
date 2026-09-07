locals {
  emails   = lookup(local.settings, "alert_emails", [])
  channels = google_monitoring_notification_channel.email[*].id
  owned    = "metadata.user_labels.\"application\"=\"${var.config.name_prefix}\""

  cpu    = lookup(local.settings, "cpu_percent", 80)
  memory = lookup(local.settings, "memory_percent", 85)
  disk   = lookup(local.settings, "disk_percent", 85)
  errors = lookup(local.settings, "error_log_threshold", 5)

  budget          = lookup(local.settings, "budget", {})
  billing_account = lookup(lookup(var.config, "gcp", {}), "billing_account", "")
}
