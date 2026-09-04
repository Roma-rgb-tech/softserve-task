output "vpc_id" {
  description = "VPC identifier, for the modules that attach to it."
  value       = one(aws_vpc.main[*].id)
}

output "internet_gateway_id" {
  description = "Internet gateway identifier, for the management route table."
  value       = one(aws_internet_gateway.main[*].id)
}

output "subnets" {
  description = "Subnet identifiers by name, for the VMs that attach to them."
  value = {
    for name, id in {
      management = one(aws_subnet.management[*].id)
      workload   = one(aws_subnet.workload[*].id)
    } : name => id if id != null
  }
}
