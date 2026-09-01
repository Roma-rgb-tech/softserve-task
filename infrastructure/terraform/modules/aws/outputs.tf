output "region" {
  description = "Provider region this module deployed into, or null when it created nothing."
  value       = local.enabled ? local.region : null
}

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

output "secret_resource_names" {
  description = "Fully qualified secret resource names, by secret ID. Never values."
  value       = { for secret_id, secret in aws_secretsmanager_secret.this : secret_id => secret.arn }
}
