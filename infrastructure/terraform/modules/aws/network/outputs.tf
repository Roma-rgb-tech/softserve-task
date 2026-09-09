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

output "database_subnet_ids" {
  description = "Subnets the DB subnet group spans. Empty when the database is not managed. They stay on the VPC main route table, so the database has no path to the internet in either direction."
  value       = sort([for subnet in aws_subnet.database : subnet.id])
}

output "database_subnet_cidrs" {
  description = "Ranges of those subnets, for the rules that let the workloads reach the database."
  value       = sort([for subnet in aws_subnet.database : subnet.cidr_block])
}
