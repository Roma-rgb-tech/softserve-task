output "runtime_identities" {
  description = "IAM role name by VM name. The VMs run as these and the secret policies are attached to these."
  value       = { for name, role in aws_iam_role.workload : name => role.name }
}

output "instance_profiles" {
  description = "Instance profile name by VM name, for the instances to assume their role."
  value       = { for name, profile in aws_iam_instance_profile.workload : name => profile.name }
}

output "key_name" {
  description = "Key pair EC2 installs into the image's default account."
  value       = one(aws_key_pair.operator[*].key_name)
}
