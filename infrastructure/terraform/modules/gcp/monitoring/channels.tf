# One channel per address rather than one channel with several: Cloud Monitoring
# email channels hold a single address, and a per-address channel can be removed
# from one policy without touching the rest.
resource "google_monitoring_notification_channel" "email" {
  count = local.enabled == 1 ? length(local.emails) : 0

  display_name = "${local.prefix} alerts: ${local.emails[count.index]}"
  type         = "email"

  labels = {
    email_address = local.emails[count.index]
  }
}
