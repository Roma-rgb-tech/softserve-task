variable "config" {
  description = "The whole project configuration, decoded from JSON."
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

variable "subnets" {
  description = "Subnet identifiers by name, from the network module."
  type        = map(string)
}

variable "security_groups" {
  description = "Application security group identifiers by workload role, from the firewall module."
  type        = map(string)
}

variable "public_ip_ids" {
  description = "Public IP resource identifier by VM name, from the addresses module."
  type        = map(string)
}

variable "identity_ids" {
  description = "Managed identity resource identifier by VM name, from the iam module."
  type        = map(string)
}

variable "runtime_identities" {
  description = "Managed identity name by VM name, from the iam module."
  type        = map(string)
}

variable "admin_username" {
  description = "Account Azure creates on every VM, from the iam module."
  type        = string
  nullable    = true
}

variable "admin_public_key" {
  description = "The operator's public key, from the iam module."
  type        = string
  nullable    = true
}

variable "minimum_boot_disk_gb" {
  description = "Smallest boot disk the Azure Ubuntu images accept. A smaller boot_disk.size_gb in the configuration is raised to this, because Azure refuses to shrink an image's disk."
  type        = number
  default     = 30
}
