variable "config" {
  description = "The whole project configuration, decoded from JSON. The module selects the VMs that target this cloud and decides for itself whether it has anything to create."
  type        = any

  validation {
    condition     = can(var.config.vms) && can(var.config.catalog)
    error_message = "config must contain a vms object and a catalog of translation tables."
  }
}
