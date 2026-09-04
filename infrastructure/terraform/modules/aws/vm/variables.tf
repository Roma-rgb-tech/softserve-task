variable "config" {
  description = "The whole project configuration, decoded from JSON."
  type        = any
}

variable "subnets" {
  description = "Subnet identifiers by name, from the network module."
  type        = map(string)
}

variable "security_groups" {
  description = "Security group identifiers by workload role, from the firewall module."
  type        = map(string)
}

variable "instance_profiles" {
  description = "Instance profile name by VM name, from the iam module."
  type        = map(string)
}

variable "runtime_identities" {
  description = "IAM role name by VM name, from the iam module."
  type        = map(string)
}

variable "key_name" {
  description = "Key pair EC2 installs into the image's default account, from the iam module."
  type        = string
}

variable "image_owner" {
  description = "AWS account that publishes the AMI. Defaults to Canonical, which builds the Ubuntu images this project uses."
  type        = string
  default     = "099720109477"
}
