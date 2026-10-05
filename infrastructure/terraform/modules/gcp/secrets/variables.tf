variable "config" {
  description = "The whole project configuration, decoded from JSON."
  type        = any
}

variable "runtime_identities" {
  description = "Service-account email by VM name, from the iam module. Access is granted to these, never to the project."
  type        = map(string)
}

variable "cluster_secret_ids" {
  description = "Secret containers named by k3s nodes that a managed cluster replaced. They are created with the others, but no VM identity is granted access: Ansible reads them from the controller with the operator's credentials."
  type        = list(string)
  default     = []
}
