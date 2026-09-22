variable "config" {
  description = "The whole project configuration, decoded from JSON, with this cloud's network block."
  type        = any
}

variable "route_table_ids" {
  description = "Route table identifier by subnet name, from the routing module."
  type        = map(string)
}

variable "next_hop" {
  description = "Network interface of the bastion, which is the tailnet subnet router for this VPC."
  type        = string
  nullable    = true
}
