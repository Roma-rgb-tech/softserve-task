variable "config" {
  description = "The whole project configuration, decoded from JSON. Absent monitoring settings mean this module creates nothing."
  type        = any
}

variable "public_ips" {
  description = "External address by VM name, from the addresses module. An uptime check needs an address to call."
  type        = map(string)
}
