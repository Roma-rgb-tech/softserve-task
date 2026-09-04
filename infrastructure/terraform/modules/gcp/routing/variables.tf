variable "config" {
  description = "The whole project configuration, decoded from JSON."
  type        = any
}

variable "network_id" {
  description = "VPC network the router attaches to, from the network module."
  type        = string
}

variable "workload_subnet_id" {
  description = "Subnet whose egress the NAT gateway translates, from the network module."
  type        = string
}
