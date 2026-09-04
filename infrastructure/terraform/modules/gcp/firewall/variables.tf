variable "config" {
  description = "The whole project configuration, decoded from JSON."
  type        = any
}

variable "network_id" {
  description = "VPC network the rules apply to, from the network module."
  type        = string
}
