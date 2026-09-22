variable "config" {
  description = "The whole project configuration, decoded from JSON. The module derives the secret containers from the VMs that target this cloud."
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

variable "principal_ids" {
  description = "Managed identity principal by VM name, from the iam module. Access is granted to these, one secret at a time, never to the vault."
  type        = map(string)
}
