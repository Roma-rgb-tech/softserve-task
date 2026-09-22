output "runtime_identities" {
  description = "Managed identity name by VM name. The VMs run as these."
  value       = { for name, identity in azurerm_user_assigned_identity.workload : name => identity.name }
}

output "identity_ids" {
  description = "Managed identity resource identifier by VM name, for the VMs to carry."
  value       = { for name, identity in azurerm_user_assigned_identity.workload : name => identity.id }
}

output "principal_ids" {
  description = "Managed identity principal by VM name. The secret role assignments are made to these."
  value       = { for name, identity in azurerm_user_assigned_identity.workload : name => identity.principal_id }
}

output "admin_username" {
  description = "Account Azure creates on every VM, with the operator's key."
  value       = local.enabled ? local.operator : null
}

output "admin_public_key" {
  description = "The operator's public key."
  value       = local.enabled ? trimspace(var.config.ssh_users[local.operator]) : null
}
