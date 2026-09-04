output "subnets" {
  description = "Subnet identifiers by name, for the VMs that attach to them."
  value       = local.subnets
}

output "security_groups" {
  description = "Security group identifiers by workload role, the identifier a VM carries to match a rule."
  value       = local.group_ids
}
