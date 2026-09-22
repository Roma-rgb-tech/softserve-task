variable "config" {
  description = "The whole project configuration, decoded from JSON. Absent monitoring settings mean this module creates nothing."
  type        = any
}

variable "resource_group_name" {
  description = "Resource group from the network module."
  type        = string
  nullable    = true
}

variable "resource_group_id" {
  description = "Resource group identifier from the network module. The budget watches everything in it."
  type        = string
  nullable    = true
}

variable "location" {
  description = "Azure region from the network module."
  type        = string
  nullable    = true
}

variable "vm_ids" {
  description = "Virtual machine resource identifier by VM name, from the vm module."
  type        = map(string)
}

variable "identity_ids" {
  description = "Managed identity resource identifier by VM name, from the iam module. The monitoring agent authenticates as the VM's own identity."
  type        = map(string)
}
