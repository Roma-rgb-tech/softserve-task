output "route_table_ids" {
  description = "Route table identifier by subnet name."
  value       = { for name, table in aws_route_table.this : name => table.id }
}
