output "security_groups" {
  description = "Security group identifiers by workload role, the identifier a VM carries to match a rule."
  value       = local.group_ids
}
