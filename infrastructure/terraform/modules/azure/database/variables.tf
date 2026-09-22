variable "config" {
  description = "The whole project configuration, decoded from JSON. An absent database block, or one that is not managed, means this module creates nothing."
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

variable "virtual_network_id" {
  description = "Virtual network the private DNS zone is linked to, so the server name resolves inside it."
  type        = string
  nullable    = true
}

variable "subnet_id" {
  description = "Subnet delegated to PostgreSQL Flexible Server, from the network module."
  type        = string
  nullable    = true
}

variable "client_cidrs" {
  description = "Ranges allowed to reach PostgreSQL. Everything else in the virtual network is refused."
  type        = list(string)
}
