output "network_id" {
  description = "VPC network identifier, for the modules that attach to it."
  value       = one(google_compute_network.main[*].id)
}

output "workload_subnet_id" {
  description = "Workload subnet identifier, for the NAT gateway."
  value       = one(google_compute_subnetwork.workload[*].id)
}

output "subnets" {
  description = "Subnet identifiers by name, for the VMs that attach to them."
  value = {
    for name, id in {
      management = one(google_compute_subnetwork.management[*].id)
      workload   = one(google_compute_subnetwork.workload[*].id)
    } : name => id if id != null
  }
}

output "database_subnet_id" {
  description = "Subnet the Private Service Connect endpoint for Cloud SQL is created in, or null when the database is not managed."
  value       = one(google_compute_subnetwork.database[*].id)
}

output "database_subnet_cidr" {
  description = "Range of that subnet, for the firewall rules that let the workloads reach it."
  value       = one(google_compute_subnetwork.database[*].ip_cidr_range)
}
