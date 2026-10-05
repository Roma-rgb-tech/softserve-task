variable "config" {
  description = "The whole project configuration, decoded from JSON."
  type        = any
}

variable "network_id" {
  description = "VPC network the cluster joins, from the network module. Null when this cloud builds nothing."
  type        = string
  nullable    = true
}
