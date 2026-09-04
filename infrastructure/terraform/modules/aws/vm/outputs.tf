output "instance_ids" {
  description = "Instance identifier by VM name, for the elastic IPs that attach to them."
  value       = { for name, instance in aws_instance.workload : name => instance.id }
}

output "vms" {
  description = "One entry per VM this module created, in the shape the root module merges across clouds. The external address is attached by the root, because the two clouds resolve it in opposite directions."
  value = {
    for name, vm in local.vms : name => {
      name             = aws_instance.workload[name].tags["Name"]
      cloud            = local.cloud
      role             = vm.role
      internal_ip      = aws_instance.workload[name].private_ip
      network_groups   = aws_instance.workload[name].vpc_security_group_ids
      runtime_identity = var.runtime_identities[name]
      secret_access    = sort(distinct(values(vm.secret_mappings)))
    }
  }
}

output "region" {
  description = "Provider region this cloud deployed into, or null when it created nothing."
  value       = length(local.selected) > 0 ? lookup(lookup(var.config.catalog.region, local.cloud, {}), local.token, null) : null
}
