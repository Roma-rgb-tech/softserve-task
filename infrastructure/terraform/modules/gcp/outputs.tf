output "region" {
  description = "Provider region this module deployed into, or null when it created nothing."
  value       = local.enabled ? local.region : null
}

output "vms" {
  description = "One entry per VM this module created, in the shape the root module merges across clouds."
  value = {
    for name, vm in local.vms : name => {
      name             = google_compute_instance.workload[name].name
      cloud            = local.cloud
      role             = vm.role
      internal_ip      = google_compute_instance.workload[name].network_interface[0].network_ip
      public_ip        = vm.assign_public_ip ? google_compute_address.public[name].address : null
      network_groups   = google_compute_instance.workload[name].tags
      runtime_identity = google_service_account.workload[name].email
      secret_access    = sort(distinct(values(vm.secret_mappings)))
    }
  }
}

output "secret_resource_names" {
  description = "Fully qualified secret resource names, by secret ID. Never values."
  value       = { for secret_id, secret in google_secret_manager_secret.this : secret_id => secret.name }
}
