output "dashboard_name" {
  description = "Workbook that plays the dashboard's part, or null when monitoring is not configured."
  value       = one(azurerm_application_insights_workbook.overview[*].display_name)
}

output "alert_action_group_id" {
  description = "Action group every alert notifies, or null when monitoring is not configured."
  value       = one(azurerm_monitor_action_group.email[*].id)
}

output "workspace_name" {
  description = "Log Analytics workspace the agents send to."
  value       = one(azurerm_log_analytics_workspace.main[*].name)
}
