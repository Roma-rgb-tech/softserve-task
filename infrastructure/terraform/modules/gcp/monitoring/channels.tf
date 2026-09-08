resource "google_monitoring_notification_channel" "email" {
  count = local.enabled == 1 ? length(local.emails) : 0

  display_name = "${local.prefix} alerts: ${local.emails[count.index]}"
  type         = "email"

  labels = {
    email_address = local.emails[count.index]
  }
}
