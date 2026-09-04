output "vms" {
  description = "One entry per VM this module created, in the shape the root module merges across clouds. The external address is attached by the root, because the two clouds resolve it in opposite directions."
  value = {
    for name, vm in local.vms : name => {
      name             = google_compute_instance.workload[name].name
      cloud            = local.cloud
      role             = vm.role
      internal_ip      = google_compute_instance.workload[name].network_interface[0].network_ip
      network_groups   = google_compute_instance.workload[name].tags
      runtime_identity = var.runtime_identities[name]
      secret_access    = sort(distinct(values(vm.secret_mappings)))
    }
  }
}

output "region" {
  description = "Provider region this cloud deployed into, or null when it created nothing."
  value       = length(local.selected) > 0 ? lookup(lookup(var.config.catalog.region, local.cloud, {}), local.token, null) : null
}
