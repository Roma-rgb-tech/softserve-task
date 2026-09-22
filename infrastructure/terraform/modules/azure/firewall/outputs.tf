output "security_groups" {
  description = "Application security group identifiers by workload role, the identifier a VM's network interface joins to match a rule."
  value       = local.group_ids
}
