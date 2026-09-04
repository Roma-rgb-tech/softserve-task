variable "config" {
  description = "The whole project configuration, decoded from JSON. The module selects the VMs that target this cloud and resolves every portable token through the catalog the file carries."
  type        = any

  validation {
    condition     = can(var.config.vms) && can(var.config.catalog)
    error_message = "config must contain a vms object and a catalog of translation tables."
  }
}

variable "subnets" {
  description = "Subnet identifiers by name, from the network module."
  type        = map(string)
}

variable "network_tags" {
  description = "Network tag by workload role, from the network module."
  type        = map(string)
}
