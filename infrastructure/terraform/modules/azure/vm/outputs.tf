output "vm_ids" {
  description = "Virtual machine resource identifier by VM name, for the alerts and agents that attach to them."
  value       = { for name, vm in azurerm_linux_virtual_machine.workload : name => vm.id }
}

output "vms" {
  description = "One entry per VM this module created, in the shape the root module merges across clouds. The external address is attached by the parent module."
  value = {
    for name, vm in local.vms : name => {
      name             = azurerm_linux_virtual_machine.workload[name].name
      cloud            = local.cloud
      role             = vm.role
      internal_ip      = azurerm_linux_virtual_machine.workload[name].private_ip_address
      network_groups   = sort([for role in vm.network_tags : var.security_groups[role]])
      runtime_identity = var.runtime_identities[name]
      secret_access    = sort(distinct(values(vm.secret_mappings)))
    }
  }
}

output "region" {
  description = "Provider region this cloud deployed into, or null when it created no VM."
  value       = length(local.selected) > 0 ? lookup(lookup(var.config.catalog.region, local.cloud, {}), local.token, null) : null
}
