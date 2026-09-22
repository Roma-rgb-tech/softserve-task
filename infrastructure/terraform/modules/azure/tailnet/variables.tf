variable "config" {
  description = "The whole project configuration, decoded from JSON, with this cloud's network block."
  type        = any
}

variable "resource_group_name" {
  description = "Resource group from the network module."
  type        = string
  nullable    = true
}

variable "location" {
  description = "Azure region from the network module."
  type        = string
  nullable    = true
}

variable "subnets" {
  description = "Subnet identifiers by name, from the network module."
  type        = map(string)
}

variable "next_hop" {
  description = "Private address of the bastion, which is the tailnet subnet router for this virtual network."
  type        = string
  nullable    = true
}
