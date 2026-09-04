variable "config" {
  description = "The whole project configuration, decoded from JSON."
  type        = any
}

variable "instance_ids" {
  description = "Instance identifier by VM name, from the vm module. EC2 attaches an elastic IP to an instance, so this module runs after the VMs exist."
  type        = map(string)
}
