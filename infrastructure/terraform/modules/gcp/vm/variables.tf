variable "config" {
  description = "The whole project configuration, decoded from JSON."
  type        = any
}

variable "subnets" {
  description = "Subnet identifiers by name, from the network module."
  type        = map(string)
}

variable "runtime_identities" {
  description = "Service-account email by VM name, from the iam module."
  type        = map(string)
}

variable "public_ips" {
  description = "External address by VM name, from the addresses module."
  type        = map(string)
}
