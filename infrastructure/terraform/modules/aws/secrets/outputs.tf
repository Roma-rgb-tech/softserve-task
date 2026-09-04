output "secret_resource_names" {
  description = "Fully qualified secret resource names, by secret ID. Never values."
  value       = { for secret_id, secret in aws_secretsmanager_secret.this : secret_id => secret.arn }
}
