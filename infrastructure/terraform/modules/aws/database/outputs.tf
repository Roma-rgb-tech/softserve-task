output "database" {
  description = "How to reach the managed database, and where its administrator password is kept. Never the password itself."
  value = local.enabled == 0 ? null : {
    host             = aws_db_instance.main[0].address
    port             = aws_db_instance.main[0].port
    database         = local.settings.database_name
    username         = local.settings.username
    connector        = null
    connection_name  = aws_db_instance.main[0].identifier
    password_secret  = one(aws_db_instance.main[0].master_user_secret[*].secret_arn)
    password_managed = true
  }
}
