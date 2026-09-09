variable "config" {
  description = "The whole project configuration, decoded from JSON. An absent database block, or one that is not managed, means this module creates nothing."
  type        = any
}

variable "network_id" {
  description = "VPC the Private Service Connect endpoint is created in, from the network module."
  type        = string
}

variable "subnet_id" {
  description = "Subnet the endpoint address is taken from, from the network module. Null when the database is not managed."
  type        = string
}
