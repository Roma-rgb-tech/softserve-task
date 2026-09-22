variable "config" {
  description = "The whole project configuration, decoded from JSON."
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
  description = "Subnet identifiers by name, from the network module. One network security group guards both."
  type        = map(string)
}
