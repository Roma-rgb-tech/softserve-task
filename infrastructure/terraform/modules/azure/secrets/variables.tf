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

variable "cluster_secret_ids" {
  description = "Secret containers named by k3s nodes that a managed cluster replaced. They are created with the others, but no VM identity is granted access: Ansible reads them from the controller with the operator's credentials."
  type        = list(string)
  default     = []
}

variable "cluster_reader" {
  description = "The managed cluster's External Secrets identity. When enabled, it may read each of secret_ids, a subset of cluster_secret_ids (Key Vault Secrets User, one secret at a time)."
  type = object({
    enabled      = bool
    principal_id = string
    secret_ids   = list(string)
  })
  default = {
    enabled      = false
    principal_id = null
    secret_ids   = []
  }
}
