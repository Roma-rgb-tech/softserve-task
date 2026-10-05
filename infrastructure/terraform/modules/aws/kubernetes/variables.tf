variable "config" {
  description = "The whole project configuration, decoded from JSON."
  type        = any
}

variable "vpc_id" {
  description = "VPC the cluster joins, from the network module. Null when this cloud builds nothing."
  type        = string
  nullable    = true
}

variable "subnets" {
  description = "Subnet identifiers by name, from the network module. The internet-facing load balancer goes into management."
  type        = map(string)
}

variable "route_table_ids" {
  description = "Route table identifier by subnet name, from the routing module. The node subnets use the workload one, which leaves through the NAT gateway."
  type        = map(string)
}
