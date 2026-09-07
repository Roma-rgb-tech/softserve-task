output "alert_topic_arn" {
  description = "SNS topic every alarm publishes to, or null when monitoring is not configured."
  value       = one(aws_sns_topic.alerts[*].arn)
}

output "log_group_name" {
  description = "CloudWatch log group the agents ship container logs to."
  value       = one(aws_cloudwatch_log_group.docker[*].name)
}

output "dashboard_name" {
  description = "CloudWatch dashboard name, or null when monitoring is not configured."
  value       = one(aws_cloudwatch_dashboard.overview[*].dashboard_name)
}
