variable "config" {
  description = "The whole project configuration, decoded from JSON. Absent monitoring settings mean this module creates nothing."
  type        = any
}
