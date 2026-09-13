output "records" {
  description = "Hostname to origin IP for every DNS-only record this module manages."
  value       = { for name, record in cloudflare_dns_record.endpoint : record.name => record.content }
}
