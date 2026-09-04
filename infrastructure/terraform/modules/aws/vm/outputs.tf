output "vms" {
  description = "One entry per VM this module created, in the shape the root module merges across clouds."
  value = {
    for name, vm in local.vms : name => {
      name             = aws_instance.workload[name].tags["Name"]
      cloud            = local.cloud
      role             = vm.role
      internal_ip      = aws_instance.workload[name].private_ip
      public_ip        = vm.assign_public_ip ? aws_eip.public[name].public_ip : null
      network_groups   = aws_instance.workload[name].vpc_security_group_ids
      runtime_identity = aws_iam_role.workload[name].name
      secret_access    = sort(distinct(values(vm.secret_mappings)))
    }
  }
}

output "runtime_identities" {
  description = "IAM role name by VM name, for the secret access policies."
  value       = { for name, role in aws_iam_role.workload : name => role.name }
}

output "region" {
  description = "Provider region this cloud deployed into, or null when it created nothing."
  value       = local.enabled ? local.region : null
}
