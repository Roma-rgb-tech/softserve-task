variable "config" {
  description = "The whole project configuration, decoded from JSON. The module derives the secret containers from the VMs that target this cloud."
  type        = any

  validation {
    condition     = can(var.config.vms) && can(var.config.catalog)
    error_message = "config must contain a vms object and a catalog of translation tables."
  }
}

variable "runtime_identities" {
  description = "Service-account email by VM name, from the vm module. Access is granted to these, never to the project."
  type        = map(string)
}
