variable "config" {
  description = "The whole project configuration, decoded from JSON."
  type        = any
}

variable "runtime_identities" {
  description = "Service-account email by VM name, from the iam module. Access is granted to these, never to the project."
  type        = map(string)
}
