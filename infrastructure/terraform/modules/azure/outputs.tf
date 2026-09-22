output "vms" {
  description = "One entry per VM this cloud created, in the shape the root module merges across clouds."
  value = {
    for name, vm in module.vm.vms :
    name => merge(vm, { public_ip = lookup(module.addresses.public_ips, name, null) })
  }
}

output "region" {
  description = "Provider region this cloud deployed into, or null when it created nothing."
  value       = module.network.location
}

output "secret_resource_names" {
  description = "Versionless Key Vault secret identifiers, by secret ID. Never values."
  value       = module.secrets.secret_resource_names
}

output "key_vault_name" {
  description = "Key Vault that holds the secrets, or null when no Azure VM reads one."
  value       = module.secrets.key_vault_name
}

output "monitoring" {
  description = "What Azure Monitor set up: the workbook, and how an alert leaves the cloud."
  value = {
    dashboard = module.monitoring.dashboard_name
    delivery  = module.monitoring.alert_action_group_id
  }
}

output "database" {
  description = "Managed PostgreSQL server name and the private hostname it answers on."
  value = {
    server_name = module.database.server_name
    fqdn        = module.database.fqdn
  }
}
