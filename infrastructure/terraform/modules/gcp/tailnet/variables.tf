variable "config" {
  description = "The whole project configuration, decoded from JSON, with this cloud's network block."
  type        = any
}

variable "network_id" {
  description = "VPC network the routes belong to, from the network module."
  type        = string
  nullable    = true
}

variable "next_hop" {
  description = "Self link of the bastion, which is the tailnet subnet router for this network."
  type        = string
  nullable    = true
}
