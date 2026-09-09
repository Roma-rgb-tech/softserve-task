output "database" {
  description = "How to reach the managed database. The password is not here: Ansible sets the application role's password from the project secret after the instance exists."
  value = local.enabled == 0 ? null : {
    host             = google_compute_address.endpoint[0].address
    port             = var.config.service_ports.postgresql
    database         = local.settings.database_name
    username         = local.settings.username
    connector        = "cloud-sql-auth-proxy"
    connection_name  = google_sql_database_instance.main[0].connection_name
    password_secret  = lookup(local.settings, "password_secret", null)
    password_managed = false
  }
}
