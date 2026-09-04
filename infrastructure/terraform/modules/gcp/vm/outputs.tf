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

output "runtime_identities" {
  description = "Service-account email by VM name, for the secret access bindings."
  value       = { for name, sa in google_service_account.workload : name => sa.email }
}

output "region" {
  description = "Provider region this cloud deployed into, or null when it created nothing."
  value       = local.enabled ? local.region : null
}
