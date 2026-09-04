output "subnets" {
  description = "Subnet identifiers by name, for the VMs that attach to them."
  value = {
    for name, id in {
      management = one(google_compute_subnetwork.management[*].id)
      workload   = one(google_compute_subnetwork.workload[*].id)
    } : name => id if id != null
  }
}

output "network_tags" {
  description = "Compute Engine network tag by workload role, the identifier a VM carries to match a firewall rule."
  value       = local.network_tags
}
