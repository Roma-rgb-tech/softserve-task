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

variable "virtual_network_name" {
  description = "Virtual network the node subnet is added to, from the network module."
  type        = string
  nullable    = true
}

variable "virtual_network_id" {
  description = "The same virtual network's identifier, for the cluster identity's role on it."
  type        = string
  nullable    = true
}
