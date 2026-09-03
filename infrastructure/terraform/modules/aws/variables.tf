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
  description = "IAM principals allowed to add new versions to every secret created here. ARNs in this module; IAM members in the GCP one."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for principal in var.secret_version_managers :
      can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(root|user/.+|role/.+)$", principal))
    ])
    error_message = "Each entry must be an IAM ARN, for example arn:aws:iam::123456789012:user/name."
  }
}

variable "image_owner" {
  description = "AWS account that publishes the AMI. Defaults to Canonical."
  type        = string
  default     = "099720109477"
}

variable "boot_disk_iops" {
  description = "Provisioned IOPS for boot volume types that require them. AWS refuses io1 and io2 volumes without it, and ignores it for gp2 and gp3."
  type        = number
  default     = 100

  validation {
    condition     = var.boot_disk_iops >= 100
    error_message = "boot_disk_iops must be at least 100, the minimum AWS accepts."
  }
}
