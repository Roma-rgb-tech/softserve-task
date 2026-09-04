variable "config" {
  description = "The whole project configuration, decoded from JSON."
  type        = any
}

variable "vpc_id" {
  description = "VPC the security groups belong to, from the network module."
  type        = string
}
