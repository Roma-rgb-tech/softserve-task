variable "config" {
  description = "The whole project configuration, decoded from JSON. The module selects the VMs that target this cloud and resolves every portable token through the catalog the file carries."
  type        = any

  validation {
    condition     = can(var.config.vms) && can(var.config.catalog)
    error_message = "config must contain a vms object and a catalog of translation tables."
  }
}

variable "enable_bastion_ssh_bootstrap" {
  description = "Temporarily allow direct bastion SSH on port 22 while Ansible configures the final SSH port."
  type        = bool
  default     = false
}

variable "secret_version_managers" {
  description = "IAM members allowed to add new versions to every secret created here."
  type        = list(string)
  default     = []
}
