output "runtime_identities" {
  description = "Service-account email by VM name. The VMs run as these and the secret bindings are granted to these."
  value       = { for name, account in google_service_account.workload : name => account.email }
}
