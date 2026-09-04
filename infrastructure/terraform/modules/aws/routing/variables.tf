variable "config" {
  description = "The whole project configuration, decoded from JSON."
  type        = any
}

variable "vpc_id" {
  description = "VPC the route tables belong to, from the network module."
  type        = string
}

variable "subnets" {
  description = "Subnet identifiers by name, from the network module."
  type        = map(string)
}

variable "internet_gateway_id" {
  description = "Internet gateway the management subnet routes through, from the network module."
  type        = string
}
