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

variable "security_groups" {
  description = "Security group identifiers by workload role, from the network module."
  type        = map(string)
}

variable "image_owner" {
  description = "AWS account that publishes the AMI. Defaults to Canonical, which builds the Ubuntu images this project uses."
  type        = string
  default     = "099720109477"
}
