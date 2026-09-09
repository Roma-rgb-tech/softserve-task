variable "config" {
  description = "The whole project configuration, decoded from JSON. Absent monitoring settings mean this module creates nothing."
  type        = any
}

variable "instance_ids" {
  description = "Instance identifier by VM name, from the vm module. CloudWatch alarms are per instance, so there is no way to watch a VM without one."
  type        = map(string)
}
