output "clouds" {
  description = "Clouds this state has resources in."
  value       = sort(local.clouds)
}

output "regions" {
  description = "Provider region per cloud in use, resolved from the portable location token."
  value = {
    for cloud, region in { gcp = module.gcp.region, aws = module.aws.region } :
    cloud => region if region != null
  }
}

output "bastion_public_ip" {
  description = "Bastion public IP."
  value       = one([for name, vm in local.vms : vm.public_ip if vm.role == "bastion"])
}

output "workload_clouds" {
  description = "Cloud each VM was created in."
  value       = { for name, vm in local.vms : name => vm.cloud }
}

output "workload_vm_names" {
  description = "VM names by workload."
  value       = { for name, vm in local.vms : name => vm.name if vm.role != "bastion" }
}

output "workload_roles" {
  description = "Roles by workload."
  value       = { for name, vm in local.vms : name => vm.role if vm.role != "bastion" }
}

output "workload_internal_ips" {
  description = "Internal IPs by workload."
  value       = { for name, vm in local.vms : name => vm.internal_ip if vm.role != "bastion" }
}

output "workload_external_ips" {
  description = "External IPs by workload."
  value       = { for name, vm in local.vms : name => vm.public_ip if vm.role != "bastion" }
}

output "workload_network_groups" {
  description = "Network group identifiers by workload. Compute Engine network tags on GCP; security group IDs on AWS."
  value       = { for name, vm in local.vms : name => vm.network_groups if vm.role != "bastion" }
}

output "workload_runtime_identities" {
  description = "Identity each workload runs as. Service-account emails on GCP; IAM role names on AWS."
  value       = { for name, vm in local.vms : name => vm.runtime_identity if vm.role != "bastion" }
}

output "workload_secret_access" {
  description = "Secret IDs each workload runtime identity may read. Names only - never values."
  value       = { for name, vm in local.vms : name => vm.secret_access if vm.role != "bastion" }
}

output "secret_ids" {
  description = "Secret container IDs created from the project configuration."
  value       = sort(distinct(concat(keys(module.gcp.secret_resource_names), keys(module.aws.secret_resource_names))))
}

output "secret_resource_names" {
  description = "Fully qualified secret resource names, by secret ID. Never values."
  value       = merge(module.gcp.secret_resource_names, module.aws.secret_resource_names)
}
