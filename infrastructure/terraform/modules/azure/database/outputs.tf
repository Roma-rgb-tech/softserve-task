output "server_name" {
  description = "PostgreSQL Flexible Server name, suffixed so a re-created server never collides with a global name still held."
  value       = one(azurerm_postgresql_flexible_server.main[*].name)
}

output "fqdn" {
  description = "Hostname the workloads connect to. It resolves only inside the linked virtual network, through the private DNS zone."
  value       = one(azurerm_postgresql_flexible_server.main[*].fqdn)
}
