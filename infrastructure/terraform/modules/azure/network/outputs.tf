output "resource_group_name" {
  description = "Resource group every Azure resource of this stand belongs to."
  value       = one(azurerm_resource_group.main[*].name)
}

output "location" {
  description = "Azure region this stand deploys into, or null when no VM targets Azure."
  value       = one(azurerm_resource_group.main[*].location)
}

output "virtual_network_id" {
  description = "Virtual network identifier, for the private DNS zone link."
  value       = one(azurerm_virtual_network.main[*].id)
}

output "subnets" {
  description = "Subnet identifiers by name, for the VMs that attach to them."
  value = {
    for name, id in {
      management = one(azurerm_subnet.management[*].id)
      workload   = one(azurerm_subnet.workload[*].id)
    } : name => id if id != null
  }
}

output "database_subnet_id" {
  description = "Subnet delegated to PostgreSQL Flexible Server. Null when the database is not managed."
  value       = one(azurerm_subnet.database[*].id)
}

output "client_cidrs" {
  description = "Ranges allowed to reach the database: the workload subnet only. The bastion reaches it through a workload, as on the other clouds."
  value       = local.count == 1 ? [var.config.network.workload_subnet_cidr] : []
}

output "virtual_network_name" {
  description = "Virtual network name, for the modules that attach to it."
  value       = one(azurerm_virtual_network.main[*].name)
}

output "resource_group_id" {
  description = "Resource group identifier, for the budget that watches it."
  value       = one(azurerm_resource_group.main[*].id)
}
