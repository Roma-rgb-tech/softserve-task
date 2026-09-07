output "notification_channels" {
  description = "Notification channel IDs alerts are delivered through. Addresses stay in the configuration."
  value       = google_monitoring_notification_channel.email[*].id
}

output "dashboard_id" {
  description = "Dashboard resource name, or null when monitoring is not configured."
  value       = one(google_monitoring_dashboard.overview[*].id)
}
