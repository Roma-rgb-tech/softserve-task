variable "config" {
  description = "The whole project configuration, decoded from JSON. An absent database block, or one that is not managed, means this module creates nothing."
  type        = any
}

variable "vpc_id" {
  description = "VPC the database security group belongs to, from the network module."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets the DB subnet group spans, from the network module. RDS requires at least two availability zones."
  type        = list(string)
}

variable "security_groups" {
  description = "Security group identifiers by workload role, from the firewall module. Only the roles that talk to the database are given a path to it."
  type        = map(string)
}
